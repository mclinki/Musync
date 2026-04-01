import 'dart:async';
import 'dart:io';
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

  WebSocket? _socket;
  final StreamController<ClientEvent> _eventController =
      StreamController.broadcast();
  final ClockSyncEngine clockSync;

  // Connection state
  bool _isConnected = false;
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
      } catch (_) {}
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
      _logger.i('Connecting to ws://$hostIp:$hostPort/musync...');

      _socket = await WebSocket.connect('ws://$hostIp:$hostPort${AppConstants.webSocketPath}')
          .timeout(const Duration(milliseconds: AppConstants.connectionTimeoutMs));

      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _logger.i('Connected to host');

      _socket!.listen(
        (data) => _handleMessage(data),
        onDone: _handleDisconnect,
        onError: _handleError,
      );

      // Send join message
      final joinMsg = ProtocolMessage.join(device: _localDevice!);
      _socket!.add(joinMsg.encode());

      _eventController.add(const ClientEvent(type: ClientEventType.connected));
      return true;
    } catch (e) {
      _logger.e('Connection failed: $e');
      _isConnected = false;

      // Try to reconnect if not manually disconnected
      if (!_userDisconnected) {
        _scheduleReconnect();
      }

      return false;
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
      if (_userDisconnected) return;

      _logger.i('Reconnect attempt $_reconnectAttempts...');
      final success = await _doConnect();

      if (success && _localDevice != null) {
        _logger.i('Reconnected! Re-syncing clocks...');
        await synchronize();
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
        _syncCompleter!.completeError(TimeoutException('Superseded by new sync'));
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
            _handlePrepare(message);
            break;
          case MessageType.play:
            _handlePlay(message);
            break;
          case MessageType.pause:
            _handlePause(message);
            break;
          case MessageType.seek:
            _handleSeek(message);
            break;
          case MessageType.skipNext:
            _handleSkipNext(message);
            break;
          case MessageType.skipPrev:
            _handleSkipPrev(message);
            break;
          case MessageType.playlistUpdate:
            _handlePlaylistUpdate(message);
            break;
          case MessageType.heartbeat:
            _handleHeartbeat();
            break;
          case MessageType.fileTransferStart:
          case MessageType.fileTransferChunk:
          case MessageType.fileTransferEnd:
            // File transfer messages are handled by the session manager
            _eventController.add(ClientEvent(
              type: ClientEventType.fileTransferMessage,
              protocolMessage: message,
            ));
            break;
          case MessageType.apkTransferOffer:
            // APK transfer offer from host
            _eventController.add(ClientEvent(
              type: ClientEventType.apkTransferOffer,
              protocolMessage: message,
            ));
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
    _sessionId = message.payload['session_id'] as String? ?? '';
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

  void _sendHeartbeat() {
    if (_isConnected && _socket != null) {
      final ack = ProtocolMessage.heartbeatAck();
      try {
        _socket!.add(ack.encode());
      } catch (_) {}
    }
  }

  void _handleDisconnect() {
    _logger.i('Disconnected from host');
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

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
    _heartbeatTimer?.cancel();

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
  fileTransferMessage,
  fileTransferBinary,
  apkTransferOffer,
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
  final ProtocolMessage? protocolMessage;
  final List<Map<String, dynamic>>? playlistTracks;
  final int? playlistCurrentIndex;
  final List<int>? binaryData; // Binary data for file transfer chunks

  const ClientEvent({
    required this.type,
    this.message,
    this.sessionId,
    this.trackSource,
    this.sourceType,
    this.startAtMs,
    this.seekPositionMs,
    this.positionMs,
    this.protocolMessage,
    this.playlistTracks,
    this.playlistCurrentIndex,
    this.binaryData,
  });
}
