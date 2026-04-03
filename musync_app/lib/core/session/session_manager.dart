import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../models/models.dart';
import '../network/websocket_server.dart';
import '../network/websocket_client.dart';
import '../network/device_discovery.dart';
import '../audio/audio_engine.dart';
import '../context/event_store.dart';
import '../context/context_manager.dart';
import '../services/file_transfer_service.dart';
import '../services/foreground_service.dart';
import '../services/firebase_service.dart';
import 'playback_coordinator.dart';

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
  DeviceDiscovery? _discovery;
  late final AudioEngine _audioEngine;
  late final FileTransferService _fileTransfer;
  late final ForegroundService _foregroundService;
  late final EventStore _eventStore;
  late final ContextManager _contextManager;
  /// CRIT-005 fix: Extracted playback coordination into dedicated class.
  late final PlaybackCoordinator _playback;

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
  final StreamController<List<ConnectedDeviceInfo>> _connectedDevicesController =
      StreamController.broadcast();
  final StreamController<bool> _allGuestsReadyController =
      StreamController.broadcast();

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Periodic connected devices update timer (host side)
  Timer? _connectedDevicesTimer;

  // Post-connection recalibration timer (slave side)
  Timer? _recalibrationTimer;

  /// Whether the session manager has been fully initialized.
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Cached file path for slave playback
  String? _cachedFilePath;

  // Periodic sync quality timer (slave side)
  Timer? _syncQualityTimer;

  SessionManager({Logger? logger}) : _logger = logger ?? Logger() {
    _audioEngine = AudioEngine(logger: _logger);
    _fileTransfer = FileTransferService(logger: _logger);
    _foregroundService = ForegroundService(logger: _logger);
    _eventStore = EventStore(logger: _logger);
    _contextManager = ContextManager(eventStore: _eventStore, logger: _logger);
    // CRIT-005 fix: Initialize extracted PlaybackCoordinator
    _playback = PlaybackCoordinator(
      audioEngine: _audioEngine,
      fileTransfer: _fileTransfer,
      contextManager: _contextManager,
      logger: _logger,
    );
  }

  /// Set the Firebase service for analytics tracking (optional).
  void setFirebaseService(FirebaseService service) {
    _firebase = service;
  }

  /// Update the device name at runtime (e.g., after user changes it in settings).
  /// Updates discovery component and local device info.
  void updateDeviceName(String name) {
    if (_discovery != null) {
      _discovery!.deviceName = name;
    }
    if (_localDevice != null) {
      _localDevice = _localDevice!.copyWith(name: name);
    }
    _logger.i('Device name updated to: $name');
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

  /// Session PIN for out-of-band authentication (CRIT-002 fix).
  /// Only available when hosting. Null when not hosting.
  String? get sessionPin => _server?.sessionPin;

  /// Audio engine for direct control.
  AudioEngine get audioEngine => _audioEngine;

  /// File transfer service.
  FileTransferService get fileTransfer => _fileTransfer;

  /// Context manager for event sourcing and state snapshots.
  ContextManager get contextManager => _contextManager;

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

  /// Stream of connected devices with sync info (for host dashboard).
  Stream<List<ConnectedDeviceInfo>> get connectedDevicesStream =>
      _connectedDevicesController.stream;

  /// Stream that emits true when all connected slaves have finished loading
  /// the current track (isSynced = true), false otherwise.
  Stream<bool> get allGuestsReadyStream => _allGuestsReadyController.stream;

  /// Discovered devices.
  Map<String, DeviceInfo> get discoveredDevices =>
      _discovery?.discoveredDevices ?? const {};

  /// Get list of connected slave devices with sync info (host only).
  List<ConnectedDeviceInfo> getConnectedDevices() {
    if (_server == null) return [];
    return _server!.slaves.values.map((slave) {
      // Find matching device info from session
      final deviceInfo = _currentSession?.slaves.firstWhere(
        (d) => d.id == slave.deviceId,
        orElse: () => DeviceInfo(
          id: slave.deviceId,
          name: slave.deviceName,
          type: DeviceType.unknown,
          ip: '',
          port: 0,
          discoveredAt: slave.connectedAt,
        ),
      );
      return ConnectedDeviceInfo(
        deviceId: slave.deviceId,
        deviceName: slave.deviceName,
        deviceType: deviceInfo?.type ?? DeviceType.unknown,
        ip: deviceInfo?.ip ?? '',
        clockOffsetMs: slave.clockOffsetMs,
        isSynced: slave.isSynced,
        connectedAt: slave.connectedAt,
        lastHeartbeat: slave.lastHeartbeat,
      );
    }).toList();
  }

  /// Initialize the session manager.
  /// Each step is isolated so one failure doesn't block the rest.
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
    try {
      _localIp = await _discovery!.getLocalIp();
      if (_localIp != null) {
        _localDevice = _localDevice!.copyWith(ip: _localIp!);
        _logger.i('Local IP: $_localIp');
      }
    } catch (e) {
      _logger.w('Failed to resolve local IP (non-critical): $e');
    }

    // Initialize audio engine (may fail on Windows/desktop)
    try {
      await _audioEngine.initialize();
    } catch (e) {
      _logger.w('Failed to initialize audio engine (non-critical): $e');
    }

    // Initialize file transfer service
    try {
      await _fileTransfer.initialize();
    } catch (e) {
      _logger.w('Failed to initialize file transfer (non-critical): $e');
    }

    // Initialize event store for context management
    try {
      await _eventStore.initialize();
    } catch (e) {
      _logger.w('Failed to initialize event store (non-critical): $e');
    }

    // Listen to discovered devices
    _subscriptions.add(
      _discovery!.devices.listen((device) {
        _devicesController.add(_discovery!.discoveredDevices.values.toList());

        final elapsed = DateTime.now().difference(device.discoveredAt).inMilliseconds;
        _firebase?.logDeviceDiscovered(
          deviceType: device.type.name,
          discoveryTimeMs: elapsed,
        );
      }),
    );

    _emitState(SessionManagerState.idle);
    _isInitialized = true;
    _logger.i('SessionManager initialized');
  }

  /// Start hosting a session.
  /// This device becomes the host and starts accepting connections.
  Future<String> hostSession({int port = kDefaultPort}) async {
    if (!_isInitialized) {
      throw Exception('SessionManager not initialized. Call initialize() first.');
    }
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
      localIp: _localIp, // HIGH-004 fix: bind to local IP
      logger: _logger,
    );
    _logger.i('Session PIN: ${_server!.sessionPin}'); // CRIT-002: Display for out-of-band sharing
    await _server!.start();

    // CRIT-005 fix: Wire up playback coordinator
    _playback.setServer(_server);
    _playback.setSession(_currentSession);
    _playback.setRole(_role);

    // Listen to server events
    _subscriptions.add(
      _server!.events.listen(_handleServerEvent),
    );

    // Start publishing via mDNS
    await _discovery?.startPublishing(port: port);

    _role = DeviceRole.host;
    _emitState(SessionManagerState.hosting);

    // Initialize context for this session
    _contextManager.initContext(_currentSession!.sessionId);
    await _contextManager.recordEvent(SessionEvent(
      sessionId: _currentSession!.sessionId,
      type: EventType.sessionCreated,
      timestamp: DateTime.now(),
    ));

    // Start foreground service to keep app alive in background
    await _foregroundService.start(title: 'MusyncMIMO - Groupe actif');

    // Start periodic connected devices updates for host dashboard
    _connectedDevicesTimer?.cancel();
    _connectedDevicesTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _emitConnectedDevices(),
    );
    // Emit initial state
    _emitConnectedDevices();

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
    String? sessionPin, // CRIT-002 fix: Session PIN for authentication
  }) async {
    if (!_isInitialized) {
      _logger.e('Cannot join session: SessionManager not initialized');
      return false;
    }
    if (_role != DeviceRole.none) {
      throw Exception('Already in a session');
    }

    _logger.i('Joining session at $hostIp:$hostPort...');

    // Reset cached file from previous session
    _cachedFilePath = null;

    _client = WebSocketClient(
      hostIp: hostIp,
      hostPort: hostPort,
      sessionPin: sessionPin, // CRIT-002 fix
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

    // CRIT-005 fix: Wire up playback coordinator
    _playback.setClient(_client);
    _playback.setRole(_role);

    // Start auto-calibration to keep clocks in sync
    _client!.clockSync.startAutoCalibration();

    // BUG-8 FIX: Do a second calibration after network stabilizes (3s)
    // Initial calibration may be noisy right after connection
    // Use cancellable Timer instead of Future.delayed (CRIT-005 fix)
    _recalibrationTimer?.cancel();
    _recalibrationTimer = Timer(const Duration(seconds: 3), () async {
      if (_client != null && _client!.isConnected) {
        _logger.i('Running post-connection recalibration...');
        try {
          await _client!.synchronize();
          _emitSyncQuality();
        } catch (e) {
          _logger.w('Post-connection recalibration failed: $e');
        }
      }
      _recalibrationTimer = null;
    });

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
    await _playback.playTrack(track, delayMs: delayMs, playlist: playlist);
    _emitState(SessionManagerState.playing);
  }

  /// Pause playback (host only).
  Future<void> pausePlayback() async {
    await _playback.pausePlayback();
    _emitState(SessionManagerState.paused);
  }

  /// Resume playback (host only).
  Future<void> resumePlayback({int delayMs = AppConstants.resumeDelayMs}) async {
    await _playback.resumePlayback(delayMs: delayMs);
    _emitState(SessionManagerState.playing);
  }

  /// Broadcast playlist update to slaves (shuffle/repeat changes).
  void broadcastPlaylistUpdate({
    required List<Map<String, dynamic>> tracks,
    required int currentIndex,
    String? repeatMode,
    bool? isShuffled,
  }) {
    _playback.broadcastPlaylistUpdate(
      tracks: tracks,
      currentIndex: currentIndex,
      repeatMode: repeatMode,
      isShuffled: isShuffled,
    );
  }

  /// Sync a track to slaves without playing it (host only).
  Future<void> syncTrackToSlaves(AudioTrack track) async {
    await _playback.syncTrackToSlaves(track);
  }

  /// Rename the current session (host only).
  Future<void> renameSession(String name) async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can rename the session');
    }
    if (_currentSession == null) {
      throw Exception('No active session to rename');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Session name cannot be empty');
    }
    _currentSession = _currentSession!.copyWith(name: trimmed);
    _logger.i('Session renamed to: $trimmed');
  }

  /// Leave the current session.
  Future<void> leaveSession() async {
    _logger.i('Leaving session...');

    // Create context snapshot before leaving
    if (_contextManager.hasContext) {
      await _contextManager.createSnapshot();
    }

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
      await _discovery?.stopPublishing();
      _server = null;
    } else if (_role == DeviceRole.slave) {
      await _client?.disconnect();
      _client = null;
    }

    // Cancel periodic sync quality timer
    _syncQualityTimer?.cancel();
    _syncQualityTimer = null;

    // Cancel post-connection recalibration timer (CRIT-005 fix)
    _recalibrationTimer?.cancel();
    _recalibrationTimer = null;

    // Cancel periodic connected devices timer
    _connectedDevicesTimer?.cancel();
    _connectedDevicesTimer = null;

    await _audioEngine.stop();

    // Reset cached state
    _cachedFilePath = null;

    // Stop foreground service
    await _foregroundService.stop();

    // Stop device discovery scanning (HIGH-011 fix)
    await _discovery?.stopScanning();
    await _discovery?.stopPublishing();

    _role = DeviceRole.none;
    _currentSession = null;
    _contextManager.clearContext();

    // CRIT-005 fix: Clear playback coordinator state
    _playback.setServer(null);
    _playback.setClient(null);
    _playback.setSession(null);
    _playback.setRole(DeviceRole.none);
    _playback.cachedFilePath = null;

    _emitState(SessionManagerState.idle);

    _logger.i('Left session');
  }

  /// Start scanning for available sessions.
  Future<void> startScanning() async {
    if (!_isInitialized) {
      _logger.w('Cannot start scanning: SessionManager not initialized');
      return;
    }
    await _discovery?.startScanning();
    // Also try subnet scan as fallback
    await _discovery?.scanSubnet();
  }

  /// Stop scanning.
  Future<void> stopScanning() async {
    await _discovery?.stopScanning();
  }

  /// Broadcast a message to all connected slaves (host only).
  Future<void> broadcast(ProtocolMessage message) async {
    if (_server == null) {
      _logger.w('Cannot broadcast: not hosting');
      return;
    }
    await _server!.broadcast(message);
  }

  /// Send a message to a specific slave (host only).
  Future<void> sendToSlave(String deviceId, ProtocolMessage message) async {
    if (_server == null) {
      _logger.w('Cannot send to slave: not hosting');
      return;
    }
    await _server!.sendToSlave(deviceId, message);
  }

  /// Send a message to the host (slave only).
  void sendToHost(ProtocolMessage message) {
    if (_client == null) {
      _logger.w('Cannot send to host: not a slave');
      return;
    }
    _client!.sendMessage(message);
  }

  /// Broadcast volume to all connected slaves (host only).
  Future<void> broadcastVolume(double volume) async {
    if (_role != DeviceRole.host || _server == null) {
      _logger.w('Cannot broadcast volume: not hosting');
      return;
    }
    await _server!.broadcastVolume(volume: volume);
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    _connectedDevicesTimer?.cancel();
    _syncQualityTimer?.cancel();

    await leaveSession();
    await _discovery?.dispose();
    await _audioEngine.dispose();
    await _fileTransfer.dispose();
    await _playback.dispose();
    await _contextManager.dispose();
    await _eventStore.dispose();
    await _stateController.close();
    await _devicesController.close();
    await _playlistUpdateController.close();
    await _syncQualityController.close();
    await _connectedDevicesController.close();
    await _allGuestsReadyController.close();
  }

  // ── Event Handlers ──

  void _handleServerEvent(ServerEvent event) {
    switch (event.type) {
      case ServerEventType.deviceConnected:
        _logger.i('Device connected: ${event.deviceName}');
        _onGuestJoinedNotification();
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
        unawaited(_contextManager.recordEvent(SessionEvent(
          sessionId: _currentSession?.sessionId ?? '',
          type: EventType.deviceJoined,
          data: {'device_id': event.deviceId, 'device_name': event.deviceName},
          timestamp: DateTime.now(),
        )));
        _checkAllGuestsReady();
        _emitState(SessionManagerState.hosting);
        break;
      case ServerEventType.deviceDisconnected:
        _logger.i('Device disconnected: ${event.deviceName}');
        _currentSession = _currentSession?.removeSlave(event.deviceId);
        _checkAllGuestsReady();
        _emitState(SessionManagerState.hosting);
        break;
      case ServerEventType.deviceReady:
        _logger.i('Device ready: ${event.deviceName}');
        _checkAllGuestsReady();
        break;
      case ServerEventType.messageReceived:
        // Binary messages are handled by the file transfer service
        if (event.data is List<int>) {
          _handleServerBinaryMessage(event.deviceId, event.data as List<int>);
        }
        break;
      case ServerEventType.guestPaused:
        _logger.i('Guest ${event.deviceName} paused at ${event.data}ms');
        // TODO: Broadcast pause to other slaves or adjust sync
        break;
      case ServerEventType.guestResumed:
        _logger.i('Guest ${event.deviceName} resumed playback');
        // TODO: Broadcast resume to other slaves or adjust sync
        break;
      case ServerEventType.error:
        _logger.e('Server error: ${event.reason}');
        break;
    }
  }

  /// Handle binary messages from the server (file transfer chunks).
  Future<void> _handleServerBinaryMessage(String deviceId, List<int> data) async {
    _logger.d('Received binary message from $deviceId (${data.length} bytes)');
    // Binary chunks are handled by the file transfer service
    // This is a placeholder - actual handling is done in the file transfer service
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
      case ClientEventType.fileTransferBinary:
        _handleFileTransferBinary(event);
        break;
      case ClientEventType.apkTransferOffer:
        // APK transfer is now handled via HTTP server, not WebSocket
        _logger.d('Ignoring APK transfer offer (now handled via HTTP)');
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
      case ClientEventType.volumeControlCommand:
        // Volume control is handled by PlayerBloc directly
        break;
    }
  }

  // ── Event Handlers (delegated to PlaybackCoordinator — CRIT-005 fix) ──

  Future<void> _handlePrepareCommand(ClientEvent event) async {
    await _playback.handlePrepareCommand(event);
  }

  Future<void> _handlePlayCommand(ClientEvent event) async {
    await _playback.handlePlayCommand(event);
    _emitState(SessionManagerState.playing);
  }

  Future<void> _handlePauseCommand(ClientEvent event) async {
    await _playback.handlePauseCommand(event);
    _emitState(SessionManagerState.paused);
  }

  Future<void> _handleSeekCommand(ClientEvent event) async {
    await _playback.handleSeekCommand(event);
  }

  void _handlePlaylistUpdateCommand(ClientEvent event) {
    _playback.handlePlaylistUpdateCommand(event, _playlistUpdateController);
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

  /// Emit connected devices list for host dashboard.
  /// HIGH-012 fix: Only emit if the list actually changed (change detection).
  List<ConnectedDeviceInfo>? _lastEmittedDevices;
  void _emitConnectedDevices() {
    if (_role != DeviceRole.host || _server == null) return;
    final devices = getConnectedDevices();
    // Only emit if the list changed (different length or different device IDs)
    if (_lastEmittedDevices != null &&
        devices.length == _lastEmittedDevices!.length) {
      final same = devices.every((d) =>
          _lastEmittedDevices!.any((old) => old.deviceId == d.deviceId));
      if (same) return; // No change, skip emission
    }
    _lastEmittedDevices = List.from(devices);
    _connectedDevicesController.add(devices);
  }

  /// Check if all connected slaves have finished loading the current track
  /// and emit the result on allGuestsReadyStream.
  void _checkAllGuestsReady() {
    if (_role != DeviceRole.host || _server == null) return;
    final slaves = _server!.slaves;
    if (slaves.isEmpty) {
      _allGuestsReadyController.add(true);
      return;
    }
    final allReady = slaves.values.every((s) => s.isSynced);
    _allGuestsReadyController.add(allReady);
  }

  /// Trigger haptic feedback to notify the host that a guest has joined.
  void _onGuestJoinedNotification() {
    unawaited(HapticFeedback.lightImpact());
  }

  // ── Delegated playback handlers (CRIT-005 fix) ──

  Future<void> _handleFileTransferMessage(ClientEvent event) async {
    await _playback.handleFileTransferMessage(event);
  }

  Future<void> _handleFileTransferBinary(ClientEvent event) async {
    await _playback.handleFileTransferBinary(event);
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

// PlaylistUpdate is defined in playback_coordinator.dart (CRIT-005 fix)

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

/// APK transfer offer received from the host.
class ApkTransferOffer {
  final String version;
  final int fileSizeBytes;

  const ApkTransferOffer({
    required this.version,
    required this.fileSizeBytes,
  });
}
