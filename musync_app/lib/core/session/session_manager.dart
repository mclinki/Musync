import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../models/models.dart';
import '../network/websocket_server.dart';
import '../network/websocket_client.dart';
import '../network/device_discovery.dart';
import '../audio/audio_engine.dart';
import '../services/file_transfer_service.dart';
import '../services/foreground_service.dart';
import '../services/firebase_service.dart';

/// High-level session manager that orchestrates all components.
///
/// This is the main entry point for the app's networking and audio logic.
/// It manages:
/// - Device discovery
/// - Session creation and joining
/// - Audio playback coordination
/// - Clock synchronization
class SessionManager {
  final Logger _logger;

  // Components
  late DeviceDiscovery _discovery;
  late final AudioEngine _audioEngine;
  late final FileTransferService _fileTransfer;
  late final ForegroundService _foregroundService;

  WebSocketServer? _server;
  WebSocketClient? _client;

  // Optional Firebase analytics (set via setFirebaseService)
  FirebaseService? _firebase;

  // State
  DeviceRole _role = DeviceRole.none;
  AudioSession? _currentSession;
  DeviceInfo? _localDevice;
  String? _localIp;

  // Stream controllers
  final StreamController<SessionManagerState> _stateController =
      StreamController.broadcast();
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController.broadcast();
  final StreamController<PlaylistUpdate> _playlistUpdateController =
      StreamController.broadcast();
  final StreamController<SyncQualityUpdate> _syncQualityController =
      StreamController.broadcast();

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Cached file path for slave playback
  String? _cachedFilePath;

  // Periodic sync quality timer (slave side)
  Timer? _syncQualityTimer;

  SessionManager({Logger? logger}) : _logger = logger ?? Logger() {
    _audioEngine = AudioEngine(logger: _logger);
    _fileTransfer = FileTransferService(logger: _logger);
    _foregroundService = ForegroundService(logger: _logger);
  }

  /// Set the Firebase service for analytics tracking (optional).
  void setFirebaseService(FirebaseService service) {
    _firebase = service;
  }

  // ── Public API ──

  /// Current role of this device.
  DeviceRole get role => _role;

  /// Current session (if any).
  AudioSession? get currentSession => _currentSession;

  /// Local device info.
  DeviceInfo? get localDevice => _localDevice;

  /// Local IP address.
  String? get localIp => _localIp;

  /// Audio engine for direct control.
  AudioEngine get audioEngine => _audioEngine;

  /// File transfer service.
  FileTransferService get fileTransfer => _fileTransfer;

  /// Stream of state changes.
  Stream<SessionManagerState> get stateStream => _stateController.stream;

  /// Stream of discovered devices.
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;

  /// Stream of client events (for slave-side UI to react to host commands).
  Stream<ClientEvent>? get clientEvents => _client?.events;

  /// Stream of playlist updates (for slave-side UI).
  Stream<PlaylistUpdate> get playlistUpdateStream =>
      _playlistUpdateController.stream;

  /// Stream of sync quality updates (for slave-side UI).
  Stream<SyncQualityUpdate> get syncQualityStream =>
      _syncQualityController.stream;

  /// Discovered devices.
  Map<String, DeviceInfo> get discoveredDevices => _discovery.discoveredDevices;

  /// Initialize the session manager.
  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    String deviceType = 'phone',
  }) async {
    _logger.i('Initializing SessionManager...');

    // Create local device info
    _localDevice = DeviceInfo(
      id: deviceId,
      name: deviceName,
      type: DeviceType.fromString(deviceType),
      ip: '', // Will be set after network discovery
      port: kDefaultPort,
      discoveredAt: DateTime.now(),
    );

    // Initialize discovery with device info
    _discovery = DeviceDiscovery(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
      logger: _logger,
    );

    // Get local IP
    _localIp = await _discovery.getLocalIp();
    if (_localIp != null) {
      _localDevice = _localDevice!.copyWith(ip: _localIp!);
      _logger.i('Local IP: $_localIp');
    }

    // Initialize audio engine
    await _audioEngine.initialize();

    // Initialize file transfer service
    await _fileTransfer.initialize();

    // Listen to discovered devices
    _subscriptions.add(
      _discovery.devices.listen((device) {
        _devicesController.add(_discovery.discoveredDevices.values.toList());

        final elapsed = DateTime.now().difference(device.discoveredAt).inMilliseconds;
        _firebase?.logDeviceDiscovered(
          deviceType: device.type.name,
          discoveryTimeMs: elapsed,
        );
      }),
    );

    _emitState(SessionManagerState.idle);
    _logger.i('SessionManager initialized');
  }

  /// Start hosting a session.
  /// This device becomes the host and starts accepting connections.
  Future<String> hostSession({int port = kDefaultPort}) async {
    if (_role != DeviceRole.none) {
      throw Exception('Already in a session');
    }

    _logger.i('Starting host session...');

    // Create session
    _currentSession = AudioSession.create(host: _localDevice!);

    // Start WebSocket server
    _server = WebSocketServer(
      port: port,
      sessionId: _currentSession!.sessionId,
      logger: _logger,
    );
    await _server!.start();

    // Listen to server events
    _subscriptions.add(
      _server!.events.listen(_handleServerEvent),
    );

    // Start publishing via mDNS
    await _discovery.startPublishing(port: port);

    _role = DeviceRole.host;
    _emitState(SessionManagerState.hosting);

    // Start foreground service to keep app alive in background
    await _foregroundService.start(title: 'MusyncMIMO - Groupe actif');

    _firebase?.logSessionStart(
      sessionId: _currentSession!.sessionId,
      role: 'host',
      deviceCount: _currentSession!.slaves.length,
    );

    _logger.i('Host session started: ${_currentSession!.sessionId}');
    return _currentSession!.sessionId;
  }

  /// Join an existing session hosted by another device.
  Future<bool> joinSession({
    required String hostIp,
    int hostPort = kDefaultPort,
  }) async {
    if (_role != DeviceRole.none) {
      throw Exception('Already in a session');
    }

    _logger.i('Joining session at $hostIp:$hostPort...');

    // Reset cached file from previous session
    _cachedFilePath = null;

    _client = WebSocketClient(
      hostIp: hostIp,
      hostPort: hostPort,
      logger: _logger,
    );

    // Listen to client events
    _subscriptions.add(
      _client!.events.listen(_handleClientEvent),
    );

    // Connect
    final connected = await _client!.connect(localDevice: _localDevice!);
    if (!connected) {
      _client = null;
      return false;
    }

    // Synchronize clocks
    final synced = await _client!.synchronize();
    if (!synced) {
      _logger.w('Clock sync failed, continuing anyway');
    }

    // Start auto-calibration to keep clocks in sync
    _client!.clockSync.startAutoCalibration();

    // Emit sync quality
    _emitSyncQuality();

    _role = DeviceRole.slave;
    _emitState(SessionManagerState.joined);

    // Start periodic sync quality updates
    _syncQualityTimer?.cancel();
    _syncQualityTimer = Timer.periodic(
      const Duration(seconds: AppConstants.autoCalibrationIntervalMs ~/ 1000),
      (_) => _emitSyncQuality(),
    );

    // Start foreground service to keep app alive in background
    await _foregroundService.start(title: 'MusyncMIMO - Connecté');

    _firebase?.logSessionStart(
      sessionId: _client!.sessionId ?? '',
      role: 'slave',
      deviceCount: 1,
    );

    _logger.i('Joined session');
    return true;
  }

  /// Start playing a track (host only).
  Future<void> playTrack(AudioTrack track, {int delayMs = AppConstants.defaultPlayDelayMs, Playlist? playlist}) async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can start playback');
    }
    if (_server == null) {
      throw Exception('Server not initialized');
    }

    _logger.i('=== HOST PLAY TRACK ===');
    _logger.i('track: ${track.title}');
    _logger.i('source: ${track.source}');
    _logger.i('sourceType: ${track.sourceType}');

    // If it's a local file and we have slaves, send the file first
    String trackSource = track.source;
    
    if (track.sourceType == AudioSourceType.localFile && _server!.slaveCount > 0) {
      _logger.i('=== SENDING FILE TO SLAVES ===');
      _logger.i('Slaves count: ${_server!.slaveCount}');
      
      final sent = await _fileTransfer.sendFile(
        filePath: track.source,
        server: _server!,
      );
      
      if (sent) {
        _logger.i('File sent successfully to all slaves');
        // Send just the filename so slaves can find it in their cache
        trackSource = track.source.split('/').last.split('\\').last;
        _logger.i('Broadcasting filename: $trackSource');
        
        // Reduced wait time for slaves to save the file
        await Future.delayed(const Duration(milliseconds: AppConstants.fileTransferWaitDelayMs));
      } else {
        _logger.w('Failed to send file, slaves may not be able to play');
      }
    }

    // Load track locally
    _logger.d('Loading track locally on host...');
    await _audioEngine.loadTrack(track);

    // Send prepare command to slaves for pre-loading
    if (_server!.slaveCount > 0) {
      _logger.i('=== BROADCASTING PREPARE COMMAND ===');
      await _server!.broadcastPrepare(
        trackSource: trackSource,
        sourceType: track.sourceType,
      );
      // Wait a bit for slaves to preload
      await Future.delayed(const Duration(milliseconds: AppConstants.prepareBroadcastDelayMs));
    }

    // Broadcast to slaves (they will load and play)
    _logger.i('=== BROADCASTING PLAY COMMAND ===');
    await _server!.broadcastPlay(
      trackSource: trackSource,
      sourceType: track.sourceType,
      delayMs: delayMs,
    );

    // Play locally
    await Future.delayed(Duration(milliseconds: delayMs));
    await _audioEngine.play();

    _currentSession = _currentSession?.copyWith(
      state: SessionState.playing,
      currentTrack: track,
      startedAt: DateTime.now(),
    );

    _firebase?.logTrackPlay(
      trackTitle: track.title,
      sourceType: track.sourceType.name,
    );

    // Broadcast playlist update to slaves
    if (_server!.slaveCount > 0 && playlist != null) {
      await _server!.broadcastPlaylistUpdate(
        tracks: playlist.tracks.map((t) => {
          'title': t.title,
          'artist': t.artist,
          'source': t.source,
          'sourceType': t.sourceType.name,
        }).toList(),
        currentIndex: playlist.currentIndex,
      );
    }

    _emitState(SessionManagerState.playing);
  }

  /// Pause playback (host only).
  Future<void> pausePlayback() async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can control playback');
    }
    if (_server == null) {
      throw Exception('Server not initialized');
    }

    final positionMs = _audioEngine.position.inMilliseconds;

    await _audioEngine.pause();
    await _server!.broadcastPause(positionMs: positionMs);

    _currentSession = _currentSession?.copyWith(state: SessionState.paused);
    _emitState(SessionManagerState.paused);
  }

  /// Resume playback (host only).
  Future<void> resumePlayback({int delayMs = AppConstants.resumeDelayMs}) async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can control playback');
    }
    if (_server == null) {
      throw Exception('Server not initialized');
    }

    final track = _currentSession?.currentTrack;
    if (track == null) return;

    final positionMs = _audioEngine.position.inMilliseconds;

    // Use filename for local files (guests have the file in cache by filename)
    String trackSource = track.source;
    if (track.sourceType == AudioSourceType.localFile) {
      trackSource = track.source.split('/').last.split('\\').last;
    }

    await _server!.broadcastPlay(
      trackSource: trackSource,
      sourceType: track.sourceType,
      delayMs: delayMs,
      seekPositionMs: positionMs,
    );

    await Future.delayed(Duration(milliseconds: delayMs));
    await _audioEngine.play();

    _currentSession = _currentSession?.copyWith(state: SessionState.playing);
    _emitState(SessionManagerState.playing);
  }

  /// Sync a track to slaves without playing it (host only).
  /// Sends the file and broadcasts a prepare command so slaves can preload.
  Future<void> syncTrackToSlaves(AudioTrack track) async {
    if (_role != DeviceRole.host) return;
    if (_server == null || _server!.slaveCount == 0) return;
    if (track.sourceType != AudioSourceType.localFile) return;

    _logger.i('Syncing track to slaves: ${track.title}');

    String trackSource = track.source;
    final sent = await _fileTransfer.sendFile(
      filePath: track.source,
      server: _server!,
    );

    if (sent) {
      trackSource = track.source.split('/').last.split('\\').last;
      _logger.i('File sent, broadcasting prepare for: $trackSource');
      // Wait for slaves to save the file before sending prepare
      await Future.delayed(const Duration(milliseconds: AppConstants.fileTransferWaitDelayMs));
      await _server!.broadcastPrepare(
        trackSource: trackSource,
        sourceType: track.sourceType,
      );
    } else {
      _logger.w('Failed to sync track to slaves');
    }
  }

  /// Leave the current session.
  Future<void> leaveSession() async {
    _logger.i('Leaving session...');

    // Log session end before clearing state
    if (_currentSession != null) {
      final duration = DateTime.now().difference(_currentSession!.createdAt);
      _firebase?.logSessionEnd(
        sessionId: _currentSession!.sessionId,
        durationSeconds: duration.inSeconds,
        deviceCount: _currentSession!.slaves.length,
      );
    }

    if (_role == DeviceRole.host) {
      await _server?.stop();
      await _discovery.stopPublishing();
      _server = null;
    } else if (_role == DeviceRole.slave) {
      await _client?.disconnect();
      _client = null;
    }

    // Cancel periodic sync quality timer
    _syncQualityTimer?.cancel();
    _syncQualityTimer = null;

    await _audioEngine.stop();

    // Reset cached state
    _cachedFilePath = null;

    // Stop foreground service
    await _foregroundService.stop();

    _role = DeviceRole.none;
    _currentSession = null;
    _emitState(SessionManagerState.idle);

    _logger.i('Left session');
  }

  /// Start scanning for available sessions.
  Future<void> startScanning() async {
    await _discovery.startScanning();
    // Also try subnet scan as fallback
    await _discovery.scanSubnet();
  }

  /// Stop scanning.
  Future<void> stopScanning() async {
    await _discovery.stopScanning();
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    await leaveSession();
    await _discovery.dispose();
    await _audioEngine.dispose();
    await _fileTransfer.dispose();
    await _stateController.close();
    await _devicesController.close();
    await _playlistUpdateController.close();
    await _syncQualityController.close();
  }

  // ── Event Handlers ──

  void _handleServerEvent(ServerEvent event) {
    switch (event.type) {
      case ServerEventType.deviceConnected:
        _logger.i('Device connected: ${event.deviceName}');
        _currentSession = _currentSession?.addSlave(
          DeviceInfo(
            id: event.deviceId,
            name: event.deviceName,
            type: DeviceType.unknown,
            ip: '',
            port: 0,
            discoveredAt: DateTime.now(),
          ),
        );
        _emitState(SessionManagerState.hosting);
        break;
      case ServerEventType.deviceDisconnected:
        _logger.i('Device disconnected: ${event.deviceName}');
        _currentSession = _currentSession?.removeSlave(event.deviceId);
        _emitState(SessionManagerState.hosting);
        break;
      case ServerEventType.deviceReady:
        _logger.i('Device ready: ${event.deviceName}');
        break;
      case ServerEventType.error:
        _logger.e('Server error: ${event.reason}');
        break;
    }
  }

  void _handleClientEvent(ClientEvent event) {
    switch (event.type) {
      case ClientEventType.connected:
        _logger.i('Connected to host');
        break;
      case ClientEventType.joined:
        _logger.i('Joined session: ${event.sessionId}');
        break;
      case ClientEventType.synced:
        _logger.i('Clock synchronized');
        _emitSyncQuality();
        break;
      case ClientEventType.prepareCommand:
        _handlePrepareCommand(event);
        break;
      case ClientEventType.playCommand:
        _handlePlayCommand(event);
        break;
      case ClientEventType.pauseCommand:
        _handlePauseCommand(event);
        break;
      case ClientEventType.seekCommand:
        _handleSeekCommand(event);
        break;
      case ClientEventType.skipNextCommand:
        _logger.i('Received skip next from host');
        // Skip is handled at the player level, just log
        break;
      case ClientEventType.skipPrevCommand:
        _logger.i('Received skip prev from host');
        // Skip is handled at the player level, just log
        break;
      case ClientEventType.playlistUpdateCommand:
        _handlePlaylistUpdateCommand(event);
        break;
      case ClientEventType.fileTransferMessage:
        _handleFileTransferMessage(event);
        break;
      case ClientEventType.disconnected:
        _logger.i('Disconnected from host');
        _role = DeviceRole.none;
        _currentSession = null;
        _emitState(SessionManagerState.idle);
        break;
      case ClientEventType.rejected:
        _logger.w('Rejected by host: ${event.message}');
        _emitState(SessionManagerState.error);
        break;
      case ClientEventType.error:
        _logger.e('Client error: ${event.message}');
        break;
      case ClientEventType.reconnecting:
        _logger.w('Reconnecting to host: ${event.message}');
        _emitState(SessionManagerState.scanning);
        break;
    }
  }

  Future<void> _handlePrepareCommand(ClientEvent event) async {
    if (event.trackSource == null) {
      _logger.w('Received prepare command with null trackSource, skipping');
      return;
    }

    _logger.i('=== PREPARE COMMAND RECEIVED ===');
    _logger.i('trackSource: ${event.trackSource}');
    _logger.i('sourceType: ${event.sourceType}');

    String trackSource = event.trackSource!;

    // If it's a local file, check if we have it in cache
    if (event.sourceType == AudioSourceType.localFile) {
      final cachePath = _fileTransfer.cachePath;
      if (cachePath == null) {
        _logger.w('No cache path available for prepare');
        return;
      }
      final cachedPath = '$cachePath/$trackSource';
      final cachedFile = File(cachedPath);

      // Retry a few times in case file transfer is still in progress
      bool found = false;
      for (int i = 0; i < 5; i++) {
        if (await cachedFile.exists()) {
          trackSource = cachedPath;
          _logger.d('File found in cache: $trackSource');
          found = true;
          break;
        }
        if (i < 4) {
          _logger.d('File not in cache yet, retrying... (${i + 1}/5)');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (!found) {
        _logger.w('File not in cache after retries, will check on play');
        return;
      }
    }

    final track = event.sourceType == AudioSourceType.localFile
        ? AudioTrack.fromFilePath(trackSource)
        : AudioTrack.fromUrl(trackSource);

    // Preload the track for faster playback
    await _audioEngine.preloadTrack(track);
    _logger.i('Track preloaded: ${track.title}');
  }

  Future<void> _handlePlayCommand(ClientEvent event) async {
    if (event.trackSource == null) {
      _logger.w('Received play command with null trackSource, skipping');
      return;
    }

    _logger.i('=== RECEIVED PLAY COMMAND ===');
    _logger.i('trackSource: ${event.trackSource}');
    _logger.i('sourceType: ${event.sourceType}');
    _logger.i('seekPositionMs: ${event.seekPositionMs}');
    _logger.i('startAtMs: ${event.startAtMs}');

    String trackSource = event.trackSource!;
    
    // If it's a local file, we need to find it in cache
    if (event.sourceType == AudioSourceType.localFile) {
      _logger.d('Looking for cached file...');
      String? cachedPath;
      
      // First check if we already have the cached path
      if (_cachedFilePath != null) {
        final file = File(_cachedFilePath!);
        if (await file.exists()) {
          cachedPath = _cachedFilePath;
          _logger.d('Using cached path from memory: $cachedPath');
        }
      }
      
      // If not, try to find the file in the cache directory
      if (cachedPath == null) {
        final cachePath = _fileTransfer.cachePath;
        if (cachePath != null) {
          final cachedFile = '$cachePath/${event.trackSource!}';
          final file = File(cachedFile);
          _logger.d('Checking cache file: $cachedFile');
          
          // Wait up to 5 seconds for the file to appear (file transfer might be in progress)
          for (int i = 0; i < AppConstants.fileWaitRetryCount; i++) {
            if (await file.exists()) {
              cachedPath = cachedFile;
              _logger.d('Found cached file after ${i + 1} attempt(s)');
              break;
            }
            _logger.d('Waiting for file... attempt ${i + 1}/${AppConstants.fileWaitRetryCount}');
            await Future.delayed(const Duration(milliseconds: AppConstants.fileWaitRetryDelayMs));
          }
        } else {
          _logger.e('No cache path available!');
        }
      }
      
      if (cachedPath != null) {
        trackSource = cachedPath;
        _logger.i('Using cached file: $trackSource');
      } else {
        _logger.e('!!! FILE NOT FOUND !!!');
        _logger.e('Event trackSource was: ${event.trackSource}');
        _logger.e('Cache path: ${_fileTransfer.cachePath}');
        _logger.e('Cached file path from memory: $_cachedFilePath');
        // List files in cache directory for debugging
        final cacheDir = _fileTransfer.cachePath != null ? Directory(_fileTransfer.cachePath!) : null;
        if (cacheDir != null && await cacheDir.exists()) {
          final files = await cacheDir.list().toList();
          _logger.e('Files in cache dir: ${files.map((f) => f.path).join(', ')}');
        } else {
          _logger.e('Cache directory does not exist');
        }
        _logger.w('File not received yet, skipping playback');
        return; // Don't emit error, just skip
      }
    } else {
      _logger.d('Source is URL, no file transfer needed');
    }

    final track = event.sourceType == AudioSourceType.localFile
        ? AudioTrack.fromFilePath(trackSource)
        : AudioTrack.fromUrl(trackSource);

    _logger.i('Creating AudioTrack: ${track.title}');
    
    try {
      _logger.d('Calling audioEngine.loadPreloaded...');
      await _audioEngine.loadPreloaded(track);
      _logger.i('AudioTrack loaded successfully');
    } catch (e, stack) {
      _logger.e('!!! FAILED TO LOAD TRACK !!!: $e');
      FirebaseService().recordError(e, stack, reason: 'loadPreloaded');
      return;
    }

    // Seek if needed
    if (event.seekPositionMs != null && event.seekPositionMs! > 0) {
      _logger.d('Seeking to position: ${event.seekPositionMs}ms');
      await _audioEngine.seek(Duration(milliseconds: event.seekPositionMs!));
    }

    // Play at scheduled time
    // Convert host's startAtMs to local time using clock offset
    int delayMs = 0;
    if (event.startAtMs != null) {
      final clockOffsetMs = _client?.clockSync.stats.offsetMs ?? 0;
      final localStartAtMs = event.startAtMs! - clockOffsetMs.round();
      delayMs = localStartAtMs - DateTime.now().millisecondsSinceEpoch;
      _logger.d('Clock offset: ${clockOffsetMs.toStringAsFixed(1)}ms, '
          'host startAt: ${event.startAtMs}, local startAt: $localStartAtMs, delay: ${delayMs}ms');
    }

    if (delayMs > 0 && delayMs < AppConstants.lateCompensationThresholdMs) {
      _logger.i('Waiting ${delayMs}ms before playing...');
      await Future.delayed(Duration(milliseconds: delayMs));
    } else if (delayMs < 0) {
      // We're late - compensate by seeking forward
      final lateMs = -delayMs;
      _logger.w('Late by ${lateMs}ms, seeking forward to compensate');
      if (lateMs < AppConstants.lateCompensationMaxCompensationMs) {
        // Compensate by seeking forward, even for large offsets
        final currentPosition = _audioEngine.position.inMilliseconds;
        await _audioEngine.seek(Duration(milliseconds: currentPosition + lateMs));
        _logger.i('Seeked to ${currentPosition + lateMs}ms to compensate for ${lateMs}ms delay');
      } else {
        _logger.e('Too late (${lateMs}ms > ${AppConstants.lateCompensationMaxCompensationMs}ms), playing from current position');
      }
    } else if (delayMs >= AppConstants.lateCompensationThresholdMs) {
      // Very far in the future - shouldn't happen, but cap the wait
      _logger.w('Delay too large (${delayMs}ms), capping to ${AppConstants.lateCompensationThresholdMs}ms');
      await Future.delayed(const Duration(milliseconds: AppConstants.lateCompensationThresholdMs));
    }

    _logger.d('Calling audioEngine.play()...');
    await _audioEngine.play();
    _logger.i('=== PLAYBACK STARTED ON SLAVE ===');
    _emitState(SessionManagerState.playing);
  }

  Future<void> _handleFileTransferMessage(ClientEvent event) async {
    if (event.protocolMessage == null) {
      _logger.w('Received file transfer message with null protocolMessage');
      return;
    }
    
    _logger.i('=== PROCESSING FILE TRANSFER MESSAGE ===');
    _logger.i('Message type: ${event.protocolMessage!.type}');
    
    final result = await _fileTransfer.handleIncomingMessage(event.protocolMessage!);
    
    if (result != null) {
      // File transfer complete, result is the local file path
      _cachedFilePath = result;
      _logger.i('=== FILE TRANSFER COMPLETE ===');
      _logger.i('File saved at: $result');
      
      // Send ACK to host
      if (_client != null) {
        final ack = ProtocolMessage.fileTransferAck();
        _client!.sendMessage(ack);
        _logger.d('Sent file transfer ACK to host');
      }

      // Auto-preload the track so it's ready when play command arrives
      try {
        final file = File(result);
        if (await file.exists()) {
          final track = AudioTrack.fromFilePath(result);
          await _audioEngine.preloadTrack(track);
          _logger.i('Auto-preloaded track after file transfer: ${track.title}');
        }
      } catch (e) {
        _logger.w('Auto-preload after transfer failed (non-critical): $e');
      }
    } else {
      _logger.d('File transfer in progress or not complete yet');
    }
  }

  Future<void> _handlePauseCommand(ClientEvent event) async {
    await _audioEngine.pause();
    _emitState(SessionManagerState.paused);
  }

  Future<void> _handleSeekCommand(ClientEvent event) async {
    if (event.positionMs != null) {
      await _audioEngine.seek(Duration(milliseconds: event.positionMs!));
    }
  }

  void _handlePlaylistUpdateCommand(ClientEvent event) {
    if (event.playlistTracks == null) return;
    _logger.i('Received playlist update: ${event.playlistTracks!.length} tracks');
    if (!_playlistUpdateController.isClosed) {
      _playlistUpdateController.add(PlaylistUpdate(
        tracks: event.playlistTracks!,
        currentIndex: event.playlistCurrentIndex ?? 0,
      ));
    }
  }

  void _emitState(SessionManagerState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _emitSyncQuality() {
    if (_client == null) return;
    final stats = _client!.clockSync.stats;
    _syncQualityController.add(SyncQualityUpdate(
      offsetMs: stats.offsetMs,
      jitterMs: stats.jitterMs,
      isCalibrated: stats.isCalibrated,
      qualityLabel: stats.qualityLabel,
    ));
    _logger.i('Sync quality emitted: offset=${stats.offsetMs.toStringAsFixed(1)}ms, '
        'jitter=${stats.jitterMs.toStringAsFixed(1)}ms, quality=${stats.qualityLabel}');

    _firebase?.logSyncQuality(
      offsetMs: stats.offsetMs,
      jitterMs: stats.jitterMs,
      quality: stats.qualityLabel,
    );
  }
}

/// States of the session manager.
enum SessionManagerState {
  idle,
  scanning,
  hosting,
  joined,
  playing,
  paused,
  error,
}

/// Playlist update received from the host.
class PlaylistUpdate {
  final List<Map<String, dynamic>> tracks;
  final int currentIndex;

  const PlaylistUpdate({
    required this.tracks,
    required this.currentIndex,
  });
}

/// Sync quality update for the guest UI.
class SyncQualityUpdate {
  final double offsetMs;
  final double jitterMs;
  final bool isCalibrated;
  final String qualityLabel;

  const SyncQualityUpdate({
    required this.offsetMs,
    required this.jitterMs,
    required this.isCalibrated,
    required this.qualityLabel,
  });
}
