import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../models/models.dart';
import 'clock_sync.dart';

/// WebSocket client that runs on slave devices.
///
/// Responsibilities:
/// - Connect to the host's WebSocket server
/// - Perform clock synchronization
/// - Receive and execute playback commands
/// - Send heartbeats
/// - Auto-reconnect on disconnect
class WebSocketClient {
  final String hostIp;
  final int hostPort;
  final Logger _logger;
  /// Session PIN for join authentication (CRIT-002 fix).
  final String? sessionPin;

  WebSocket? _socket;
  final StreamController<ClientEvent> _eventController =
      StreamController.broadcast();
  final ClockSyncEngine clockSync;

  // Connection state
  bool _isConnected = false;
  bool _isAuthenticated = false; // Set to true only after receiving welcome message
  bool _isReconnecting = false;
  bool _userDisconnected = false;
  String? _sessionId;
  DeviceInfo? _localDevice;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Reconnection config
  static const int _maxReconnectAttempts = AppConstants.maxReconnectAttempts;
  static const Duration _initialReconnectDelay = Duration(milliseconds: AppConstants.initialReconnectDelayMs);
  static const Duration _maxReconnectDelay = Duration(milliseconds: AppConstants.maxReconnectDelayMs);
  int _reconnectAttempts = 0;

  // Sync state
  static const int _maxSyncAttempts = AppConstants.maxSyncAttempts;
  Completer<ClockSample>? _syncCompleter;
  int? _syncT1;

  WebSocketClient({
    required this.hostIp,
    required this.hostPort,
    this.sessionPin,
    Logger? logger,
  })  : _logger = logger ?? Logger(),
        clockSync = ClockSyncEngine();

  // ── Public API ──

  /// Stream of client events.
  Stream<ClientEvent> get events => _eventController.stream;

  /// Whether the client is connected to the host.
  bool get isConnected => _isConnected;

  /// Whether the client is attempting to reconnect.
  bool get isReconnecting => _isReconnecting;

  /// The session ID received from the host.
  String? get sessionId => _sessionId;

  /// Send a message to the host.
  void sendMessage(ProtocolMessage message) {
    if (_socket != null && _isConnected) {
      try {
        _socket!.add(message.encode());
      } catch (e) {
        _logger.e('Failed to send message: $e');
      }
    }
  }

  /// Connect to the host WebSocket server.
  Future<bool> connect({required DeviceInfo localDevice}) async {
    // Close existing connection if any (C4 fix: prevent socket leak on re-connect)
    if (_isConnected && _socket != null) {
      try {
        await _socket!.close();
      } catch (_) {}
      _socket = null;
      _isConnected = false;
    }
    _localDevice = localDevice;
    _userDisconnected = false;
    _reconnectAttempts = 0;
    return _doConnect();
  }

  /// Disconnect from the host (no auto-reconnect).
  Future<void> disconnect() async {
    _userDisconnected = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _isReconnecting = false;

    // Stop auto-calibration
    clockSync.stopAutoCalibration();

    if (_socket != null && _isConnected) {
      try {
        final disconnectMsg = ProtocolMessage(type: MessageType.disconnect);
        _socket!.add(disconnectMsg.encode());
        await _socket!.close();
      } catch (e) {
        _logger.d('Disconnect error: $e');
      }
    }

    _isConnected = false;
    _socket = null;
    _logger.i('Disconnected from host');
  }

  /// Perform clock synchronization with the host.
  /// Returns a future that completes when sync is done.
  Future<bool> synchronize() async {
    _logger.i('Starting clock synchronization...');

    for (int i = 0; i < _maxSyncAttempts; i++) {
      final samples = <ClockSample>[];

      for (int j = 0; j < 8; j++) {
        try {
          final sample = await _performSyncExchange();
          samples.add(sample);
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          _logger.w('Sync exchange failed: $e');
        }
      }

      if (samples.length >= 3) {
        // Process samples into clock sync engine
        for (final sample in samples) {
          clockSync.processSyncResponse(sample);
        }

        // Calibrate directly from collected samples
        clockSync.calibrateFromSamples(samples);
        _logger.i('Clock sync successful on attempt $i');
        _eventController.add(const ClientEvent(type: ClientEventType.synced));
        return true;
      }

      _logger.w('Sync attempt $i failed, retrying...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _logger.e('Clock sync failed after $_maxSyncAttempts attempts');
    _eventController.add(const ClientEvent(
      type: ClientEventType.error,
      message: 'Clock synchronization failed',
    ));
    return false;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _userDisconnected = true;
    // HIGH-013 fix: Cancel reconnect timer BEFORE disconnecting
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await disconnect();
    await _eventController.close();
    clockSync.dispose();
  }

  // ── Connection ──

  Future<bool> _doConnect() async {
    if (_localDevice == null) {
      _logger.e('Cannot connect: no local device info');
      return false;
    }

    try {
      final scheme = AppConstants.useTls ? 'wss' : 'ws';
      final uri = '$scheme://$hostIp:$hostPort${AppConstants.webSocketPath}';
      _logger.i('Connecting to $uri...');

      if (AppConstants.useTls) {
        _socket = await _connectWss(uri);
      } else {
        _socket = await WebSocket.connect(uri)
            .timeout(const Duration(milliseconds: AppConstants.connectionTimeoutMs));
      }

      _isConnected = true;
      _isAuthenticated = false; // Only set to true after welcome message (H1 fix)
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _logger.i('Connected to host');

      _socket!.listen(
        (data) => _handleMessage(data),
        onDone: _handleDisconnect,
        onError: _handleError,
      );

      // Send join message with session PIN (CRIT-002 fix)
      final joinMsg = ProtocolMessage.join(device: _localDevice!, sessionPin: sessionPin);
      _socket!.add(joinMsg.encode());

      // H4 fix: Check if user disconnected while we were connecting
      if (_userDisconnected) {
        await _socket!.close();
        _socket = null;
        _isConnected = false;
        return false;
      }

      _eventController.add(const ClientEvent(type: ClientEventType.connected));
      return true;
    } catch (e) {
      _logger.e('Connection failed: $e');
      _isConnected = false;
      _isReconnecting = false; // C1 fix: reset flag so reconnect can proceed

      // Try to reconnect if not manually disconnected
      if (!_userDisconnected) {
        _scheduleReconnect();
      }

      return false;
    }
  }

  /// Generate a random Sec-WebSocket-Key (16 bytes base64-encoded).
  static String _generateWebSocketKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Connect via WSS using HttpClient with custom certificate validation.
  ///
  /// HttpClient properly handles HTTP response parsing internally, and
  /// `detachSocket()` returns a fresh socket that hasn't been listened to,
  /// avoiding the "Stream has already been listened to" error.
  Future<WebSocket> _connectWss(String uri) async {
    final expectedFingerprint = AppConstants.expectedCertFingerprint.trim();

    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        if (expectedFingerprint.isNotEmpty) {
          final actualFingerprint = cert.sha1
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':')
              .toUpperCase();
          final match = actualFingerprint == expectedFingerprint.toUpperCase();
          if (!match) {
            _logger.e('Certificate pinning failed! Expected: $expectedFingerprint, Got: $actualFingerprint');
          }
          return match;
        }
        _logger.w('⚠️ No cert fingerprint configured — accepting any certificate (CRIT-001)');
        return true;
      };

    try {
      final uriObj = Uri.parse(uri);
      final httpsUri = uriObj.replace(scheme: 'https');

      final request = await httpClient.getUrl(httpsUri)
          .timeout(const Duration(milliseconds: AppConstants.connectionTimeoutMs));

      // WebSocket upgrade headers
      request.headers.set(HttpHeaders.upgradeHeader, 'websocket');
      request.headers.set(HttpHeaders.connectionHeader, 'Upgrade');
      request.headers.set('Sec-WebSocket-Key', _generateWebSocketKey());
      request.headers.set('Sec-WebSocket-Version', '13');

      final response = await request.close()
          .timeout(const Duration(milliseconds: AppConstants.connectionTimeoutMs));

      if (response.statusCode != 101) {
        throw Exception('WebSocket upgrade failed: ${response.statusCode}');
      }

      // detachSocket() returns a fresh socket after HTTP headers are consumed
      final socket = await response.detachSocket();
      try {
        return WebSocket.fromUpgradedSocket(socket, serverSide: false);
      } catch (e) {
        socket.destroy();
        rethrow;
      }
    } finally {
      httpClient.close(force: true);
    }
  }

  // ── Auto-Reconnection ──

  void _scheduleReconnect() {
    if (_userDisconnected) return;
    if (_isReconnecting) return;

    _isReconnecting = true;
    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      _logger.e('Max reconnect attempts ($_maxReconnectAttempts) reached');
      _isReconnecting = false;
      _eventController.add(const ClientEvent(
        type: ClientEventType.error,
        message: 'Connection lost: max reconnect attempts reached',
      ));
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
    final delayMs = (_initialReconnectDelay.inMilliseconds *
            (1 << (_reconnectAttempts - 1)))
        .clamp(_initialReconnectDelay.inMilliseconds,
            _maxReconnectDelay.inMilliseconds);

    _logger.i(
        'Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delayMs}ms');

    _eventController.add(ClientEvent(
      type: ClientEventType.reconnecting,
      message: 'Reconnecting... (attempt $_reconnectAttempts)',
    ));

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      try { // C2 fix: wrap async timer callback in try/catch
        if (_userDisconnected) return;

        _logger.i('Reconnect attempt $_reconnectAttempts...');
        final success = await _doConnect();

        if (success && _localDevice != null) {
          _logger.i('Reconnected! Re-syncing clocks...');
          final syncOk = await synchronize();
          if (!syncOk) { // H5 fix: emit event on sync failure after reconnect
            _eventController.add(const ClientEvent(
              type: ClientEventType.error,
              message: 'Clock sync failed after reconnect',
            ));
          }
        }
      } catch (e) {
        _logger.e('Reconnect failed: $e');
        _isReconnecting = false;
        _scheduleReconnect();
      }
    });
  }

  // ── Internal ──

  Future<ClockSample> _performSyncExchange() async {
    if (_socket == null || !_isConnected) {
      throw Exception('Not connected');
    }

    // Clean up any previous pending sync
    if (_syncCompleter != null) {
      if (!_syncCompleter!.isCompleted) {
        try { // H3 fix: prevent StateError if completer completed between check and call
          _syncCompleter!.completeError(TimeoutException('Superseded by new sync'));
        } catch (_) {}
      }
      _syncCompleter = null;
    }

    _syncT1 = DateTime.now().millisecondsSinceEpoch;
    _syncCompleter = Completer<ClockSample>();

    final request = ProtocolMessage.syncRequest();
    _socket!.add(request.encode());

    return _syncCompleter!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _syncCompleter = null;
        _syncT1 = null;
        throw TimeoutException('Sync exchange timed out');
      },
    );
  }

  void _handleMessage(dynamic data) {
    try {
      if (data is String) {
        // Handle JSON message
        final message = ProtocolMessage.decode(data);

        switch (message.type) {
          case MessageType.welcome:
            _handleWelcome(message);
            break;
          case MessageType.reject:
            _handleReject(message);
            break;
          case MessageType.syncRequest:
            _handleHostSyncRequest(message);
            break;
          case MessageType.syncResponse:
            _handleSyncResponse(message);
            break;
          case MessageType.clockAdjust:
            _handleClockAdjust(message);
            break;
          case MessageType.prepare:
            if (!_isAuthenticated) break; // H1 fix
            _handlePrepare(message);
            break;
          case MessageType.play:
            if (!_isAuthenticated) break; // H1 fix
            _handlePlay(message);
            break;
          case MessageType.pause:
            if (!_isAuthenticated) break; // H1 fix
            _handlePause(message);
            break;
          case MessageType.seek:
            if (!_isAuthenticated) break; // H1 fix
            _handleSeek(message);
            break;
          case MessageType.skipNext:
            if (!_isAuthenticated) break; // H1 fix
            _handleSkipNext(message);
            break;
          case MessageType.skipPrev:
            if (!_isAuthenticated) break; // H1 fix
            _handleSkipPrev(message);
            break;
          case MessageType.playlistUpdate:
            if (!_isAuthenticated) break; // H1 fix
            _handlePlaylistUpdate(message);
            break;
          case MessageType.heartbeat:
            _handleHeartbeat();
            break;
          case MessageType.fileTransferStart:
          case MessageType.fileTransferChunk:
          case MessageType.fileTransferEnd:
            if (!_isAuthenticated) break; // H1 fix
            // File transfer messages are handled by the session manager
            _eventController.add(ClientEvent(
              type: ClientEventType.fileTransferMessage,
              protocolMessage: message,
            ));
            break;
          case MessageType.apkTransferOffer:
            if (!_isAuthenticated) break; // H1 fix
            // APK transfer offer from host
            _eventController.add(ClientEvent(
              type: ClientEventType.apkTransferOffer,
              protocolMessage: message,
            ));
            break;
          case MessageType.volumeControl:
            if (!_isAuthenticated) break; // H1 fix
            _handleVolumeControl(message);
            break;
          case MessageType.contextSync:
            if (!_isAuthenticated) break; // H1 fix
            _handleContextSync(message);
            break;
          default:
            _logger.d('Unhandled message type: ${message.type}');
        }
      } else if (data is List<int>) {
        // Handle binary data (file transfer chunks)
        _eventController.add(ClientEvent(
          type: ClientEventType.fileTransferBinary,
          binaryData: data,
        ));
      } else {
        _logger.w('Received unknown message type: ${data.runtimeType}');
      }
    } catch (e) {
      _logger.e('Error handling message: $e');
    }
  }

  void _handleWelcome(ProtocolMessage message) {
    _isAuthenticated = true; // H1 fix: only now can commands be processed
    _sessionId = message.payload['session_id'] as String?;
    _logger.i('Joined session: $_sessionId');

    // Start heartbeat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.clientHeartbeatIntervalMs),
      (_) => _sendHeartbeat(),
    );

    _eventController.add(ClientEvent(
      type: ClientEventType.joined,
      sessionId: _sessionId,
    ));
  }

  void _handleReject(ProtocolMessage message) {
    final reason = message.payload['reason'] as String? ?? 'Unknown reason';
    _logger.w('Join rejected: $reason');
    // C6 fix: close socket and reset state on rejection
    _isConnected = false;
    _isAuthenticated = false;
    _heartbeatTimer?.cancel();
    _socket?.close();
    _eventController.add(ClientEvent(
      type: ClientEventType.rejected,
      message: reason,
    ));
  }

  void _handleHostSyncRequest(ProtocolMessage message) {
    // Host is requesting a sync exchange from us
    // t2 = time we received the request, t3 = time we send the response
    final t2 = DateTime.now().millisecondsSinceEpoch;
    final t1 = message.timestampMs;
    final t3 = DateTime.now().millisecondsSinceEpoch;
    final response = ProtocolMessage.syncResponse(t1: t1, t2: t2, t3: t3);
    _socket?.add(response.encode());
  }

  void _handleSyncResponse(ProtocolMessage message) {
    if (_syncCompleter == null || _syncCompleter!.isCompleted) {
      _logger.d('Received syncResponse but no pending sync request');
      return;
    }

    if (_syncT1 == null) {
      _logger.w('Received syncResponse but _syncT1 is null');
      return;
    }

    final t1 = _syncT1!;
    final t2 = (message.payload['t2'] as num?)?.toInt() ?? 0;
    final t3 = (message.payload['t3'] as num?)?.toInt() ?? 0;
    final t4 = DateTime.now().millisecondsSinceEpoch;

    _syncCompleter!.complete(ClockSample(t1, t2, t3, t4));
    _syncCompleter = null;
    _syncT1 = null;
  }

  void _handleClockAdjust(ProtocolMessage message) {
    final offsetMs = (message.payload['offset_ms'] as num?)?.toDouble() ?? 0.0;
    final driftPpm = (message.payload['drift_ppm'] as num?)?.toDouble() ?? 0.0;
    _logger.d('Clock adjust: offset=$offsetMs, drift=$driftPpm');
  }

  void _handlePrepare(ProtocolMessage message) {
    final trackSource = message.payload['track_source'] as String? ?? '';
    final sourceTypeStr = message.payload['source_type'] as String? ?? 'localFile';

    final sourceType = AudioSourceType.values.firstWhere(
      (e) => e.name == sourceTypeStr,
      orElse: () => AudioSourceType.localFile,
    );

    _logger.i('Received prepare command: source=$trackSource');

    _eventController.add(ClientEvent(
      type: ClientEventType.prepareCommand,
      trackSource: trackSource,
      sourceType: sourceType,
    ));
  }

  void _handlePlay(ProtocolMessage message) {
    final startAtMs = (message.payload['start_at_ms'] as num?)?.toInt() ?? 0;
    final trackSource = message.payload['track_source'] as String? ?? '';
    final sourceTypeStr = message.payload['source_type'] as String? ?? 'localFile';
    final seekPositionMs = (message.payload['seek_position_ms'] as num?)?.toInt() ?? 0;

    final sourceType = AudioSourceType.values.firstWhere(
      (e) => e.name == sourceTypeStr,
      orElse: () => AudioSourceType.localFile,
    );

    _logger.i('Received play command: start_at=$startAtMs, source=$trackSource');

    _eventController.add(ClientEvent(
      type: ClientEventType.playCommand,
      trackSource: trackSource,
      sourceType: sourceType,
      startAtMs: startAtMs,
      seekPositionMs: seekPositionMs,
    ));
  }

  void _handlePause(ProtocolMessage message) {
    final positionMs = message.payload['position_ms'] as int? ?? 0;
    _logger.i('Received pause command at position $positionMs');

    _eventController.add(ClientEvent(
      type: ClientEventType.pauseCommand,
      positionMs: positionMs,
    ));
  }

  void _handleSeek(ProtocolMessage message) {
    final positionMs = (message.payload['position_ms'] as num?)?.toInt() ?? 0;
    _logger.i('Received seek command to $positionMs');

    _eventController.add(ClientEvent(
      type: ClientEventType.seekCommand,
      positionMs: positionMs,
    ));
  }

  void _handleSkipNext(ProtocolMessage message) {
    _logger.i('Received skip next command');
    _eventController.add(const ClientEvent(
      type: ClientEventType.skipNextCommand,
    ));
  }

  void _handleSkipPrev(ProtocolMessage message) {
    _logger.i('Received skip prev command');
    _eventController.add(const ClientEvent(
      type: ClientEventType.skipPrevCommand,
    ));
  }

  void _handlePlaylistUpdate(ProtocolMessage message) {
    final tracksRaw = message.payload['tracks'];
    final tracks = tracksRaw is List
        ? tracksRaw
            .whereType<Map>()
            .map((t) => Map<String, dynamic>.from(t))
            .toList()
        : <Map<String, dynamic>>[];
    final currentIndex = (message.payload['current_index'] as num?)?.toInt() ?? 0;
    _logger.i('Received playlist update: ${tracks.length} tracks, index=$currentIndex');

    _eventController.add(ClientEvent(
      type: ClientEventType.playlistUpdateCommand,
      playlistTracks: tracks,
      playlistCurrentIndex: currentIndex,
    ));
  }

  void _handleHeartbeat() {
    final ack = ProtocolMessage.heartbeatAck();
    _socket?.add(ack.encode());
  }

  void _handleVolumeControl(ProtocolMessage message) {
    final volume = (message.payload['volume'] as num?)?.toDouble() ?? 1.0;
    _logger.i('Received volume control: $volume');
    _eventController.add(ClientEvent(
      type: ClientEventType.volumeControlCommand,
      volume: volume,
    ));
  }

  /// Handle full session context sync from host (AGENT-9).
  /// Used when a slave reconnects and needs to restore its state.
  void _handleContextSync(ProtocolMessage message) {
    final payload = message.payload;

    // Validate version
    final version = (payload['version'] as num?)?.toInt() ?? 1;
    if (version > 2) {
      _logger.w('Context version mismatch: $version (expected <= 2)');
    }

    final sessionId = payload['session_id'] as String?;
    final state = payload['state'] as String?;
    final positionMs = (payload['position_ms'] as num?)?.toInt() ?? 0;
    final volume = (payload['volume'] as num?)?.toDouble() ?? 1.0;
    final serverTimeMs = (payload['server_time_ms'] as num?)?.toInt();

    _logger.i(
      'Received contextSync: session=$sessionId, state=$state, '
      'position=${positionMs}ms, volume=$volume, version=$version',
    );

    _eventController.add(ClientEvent(
      type: ClientEventType.contextSyncCommand,
      sessionId: sessionId,
      positionMs: positionMs,
      volume: volume,
      contextData: {
        'session_id': sessionId,
        'state': state,
        'position_ms': positionMs,
        'volume': volume,
        'current_track': payload['current_track'],
        'playlist_tracks': payload['playlist_tracks'],
        'current_index': payload['current_index'],
        'repeat_mode': payload['repeat_mode'],
        'is_shuffled': payload['is_shuffled'],
        'server_time_ms': serverTimeMs,
        'version': version,
      },
    ));
  }

  void _sendHeartbeat() {
    if (_isConnected && _socket != null) {
      // C7 fix: send heartbeat (ping), not heartbeatAck — server expects pings from client
      final heartbeat = ProtocolMessage.heartbeat();
      try {
        _socket!.add(heartbeat.encode());
      } catch (e) {
        _logger.d('Heartbeat send error: $e');
      }
    }
  }

  void _handleDisconnect() {
    if (!_isConnected) return; // MED-003 fix: idempotent
    _logger.i('Disconnected from host');
    _isConnected = false;
    _isAuthenticated = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null; // LOW-002 fix: null after cancel

    if (!_userDisconnected) {
      _logger.w('Unexpected disconnect, will attempt reconnect');
      _eventController.add(const ClientEvent(
        type: ClientEventType.disconnected,
        message: 'Connection lost, reconnecting...',
      ));
      _scheduleReconnect();
    } else {
      _eventController.add(const ClientEvent(type: ClientEventType.disconnected));
    }
  }

  void _handleError(dynamic error) {
    _logger.e('WebSocket error: $error');
    _isConnected = false;
    _isAuthenticated = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel(); // H2 fix: cancel reconnect timer in error handler too

    if (!_userDisconnected) {
      _scheduleReconnect();
    }

    _eventController.add(ClientEvent(
      type: ClientEventType.error,
      message: error.toString(),
    ));
  }
}

// ── Client Events ──

enum ClientEventType {
  connected,
  disconnected,
  reconnecting,
  joined,
  rejected,
  synced,
  prepareCommand,
  playCommand,
  pauseCommand,
  seekCommand,
  skipNextCommand,
  skipPrevCommand,
  playlistUpdateCommand,
  volumeControlCommand,
  fileTransferMessage,
  fileTransferBinary,
  apkTransferOffer,
  contextSyncCommand,   // AGENT-9: Full session context received from host
  error,
}

class ClientEvent {
  final ClientEventType type;
  final String? message;
  final String? sessionId;
  final String? trackSource;
  final AudioSourceType? sourceType;
  final int? startAtMs;
  final int? seekPositionMs;
  final int? positionMs;
  final double? volume;
  final ProtocolMessage? protocolMessage;
  final List<Map<String, dynamic>>? playlistTracks;
  final int? playlistCurrentIndex;
  final List<int>? binaryData;
  final Map<String, dynamic>? contextData; // AGENT-9: Full context payload

  const ClientEvent({
    required this.type,
    this.message,
    this.sessionId,
    this.trackSource,
    this.sourceType,
    this.startAtMs,
    this.seekPositionMs,
    this.positionMs,
    this.volume,
    this.protocolMessage,
    this.playlistTracks,
    this.playlistCurrentIndex,
    this.binaryData,
    this.contextData,
  });
}
