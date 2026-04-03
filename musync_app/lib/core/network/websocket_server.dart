import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../models/models.dart';
import 'clock_sync.dart';

/// Represents a connected slave device.
class ConnectedSlave {
  final String deviceId;
  final String deviceName;
  final WebSocket socket;
  final DateTime connectedAt;
  DateTime lastHeartbeat;
  double clockOffsetMs;
  bool isSynced;

  ConnectedSlave({
    required this.deviceId,
    required this.deviceName,
    required this.socket,
    required this.connectedAt,
    DateTime? lastHeartbeat,
    this.clockOffsetMs = 0,
    this.isSynced = false,
  }) : lastHeartbeat = lastHeartbeat ?? connectedAt;
}

/// WebSocket server that runs on the host device.
///
/// Responsibilities:
/// - Accept connections from slave devices
/// - Handle clock synchronization requests
/// - Broadcast playback commands to all slaves
/// - Monitor slave heartbeats
class WebSocketServer {
  final int port;
  final Logger _logger;
  final String sessionId;

  HttpServer? _server;
  final Map<String, ConnectedSlave> _slaves = {};
  final StreamController<ServerEvent> _eventController = StreamController.broadcast();

  // Heartbeat monitoring
  Timer? _heartbeatTimer;
  static const int _heartbeatIntervalSeconds = AppConstants.serverHeartbeatIntervalMs ~/ 1000;
  static const int _heartbeatTimeoutSeconds = AppConstants.serverHeartbeatTimeoutMs ~/ 1000;

  // Clock sync for host
  final ClockSyncEngine clockSync = ClockSyncEngine();

  WebSocketServer({
    required this.port,
    required this.sessionId,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  // ── Public API ──

  /// Stream of server events (device connected, disconnected, etc.)
  Stream<ServerEvent> get events => _eventController.stream;

  /// Currently connected slaves.
  Map<String, ConnectedSlave> get slaves => UnmodifiableMapView(_slaves);

  /// Number of connected slaves.
  int get slaveCount => _slaves.length;

  /// Start the WebSocket server.
  Future<void> start() async {
    try {
      if (AppConstants.useTls) {
        final securityContext = await _createSecurityContext();
        _server = await HttpServer.bindSecure(
          InternetAddress.anyIPv4,
          port,
          securityContext,
        );
        _logger.i('WebSocket server (WSS) started on port $port');
      } else {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _logger.i('WebSocket server started on port $port');
      }

      _server!.listen(_handleRequest);

      // Start heartbeat monitoring
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _heartbeatIntervalSeconds),
        (_) => _checkHeartbeats(),
      );
    } catch (e) {
      _logger.e('Failed to start WebSocket server: $e');
      rethrow;
    }
  }

  /// Create a SecurityContext with a self-signed certificate for WSS.
  Future<SecurityContext> _createSecurityContext() async {
    final keyPair = CryptoUtils.generateRSAKeyPair();
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;

    final dn = {
      'CN': 'musync.local',
      'O': 'MusyncMIMO',
      'C': 'US',
    };

    final csr = X509Utils.generateRsaCsrPem(dn, privateKey, publicKey);
    final certificatePem = X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650);
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    final context = SecurityContext()
      ..usePrivateKeyBytes(privateKeyPem.codeUnits)
      ..useCertificateChainBytes(certificatePem.codeUnits);

    return context;
  }

  /// Stop the server and disconnect all slaves.
  Future<void> stop() async {
    _heartbeatTimer?.cancel();

    for (final slave in _slaves.values) {
      await slave.socket.close();
    }
    _slaves.clear();

    await _server?.close();
    _server = null;

    _logger.i('WebSocket server stopped');
  }

  /// Broadcast a prepare command to all slaves for pre-loading.
  Future<void> broadcastPrepare({
    required String trackSource,
    required AudioSourceType sourceType,
  }) async {
    final message = ProtocolMessage.prepare(
      trackSource: trackSource,
      sourceType: sourceType,
    );

    _logger.i('Broadcasting prepare: source=$trackSource');
    await broadcast(message);
  }

  /// Broadcast a play command to all slaves.
  Future<void> broadcastPlay({
    required String trackSource,
    required AudioSourceType sourceType,
    int delayMs = AppConstants.defaultPlayDelayMs,
    int seekPositionMs = 0,
  }) async {
    // Adaptive delay: add jitter compensation if network is unstable
    int effectiveDelay = delayMs;
    final jitter = clockSync.stats.jitterMs;
    if (jitter > 5) {
      final compensation = (jitter * 2).round();
      effectiveDelay += compensation;
      _logger.d('Adaptive delay: base=$delayMs + jitter_comp=$compensation = $effectiveDelay');
    }

    final startAtMs = clockSync.syncedTimeMs + effectiveDelay;

    final message = ProtocolMessage.play(
      startAtMs: startAtMs,
      trackSource: trackSource,
      sourceType: sourceType,
      seekPositionMs: seekPositionMs,
    );

    _logger.i('Broadcasting play: start_at=$startAtMs, source=$trackSource');
    await broadcast(message);
  }

  /// Broadcast a pause command to all slaves.
  Future<void> broadcastPause({int positionMs = 0}) async {
    final message = ProtocolMessage.pause(positionMs: positionMs);
    _logger.i('Broadcasting pause at position $positionMs');
    await broadcast(message);
  }

  /// Broadcast a seek command to all slaves.
  Future<void> broadcastSeek({required int positionMs}) async {
    final message = ProtocolMessage.seek(positionMs: positionMs);
    _logger.i('Broadcasting seek to $positionMs');
    await broadcast(message);
  }

  /// Broadcast a skip-next command to all slaves.
  Future<void> broadcastSkipNext() async {
    final message = ProtocolMessage.skipNext();
    _logger.i('Broadcasting skip next');
    await broadcast(message);
  }

  /// Broadcast a skip-prev command to all slaves.
  Future<void> broadcastSkipPrev() async {
    final message = ProtocolMessage.skipPrev();
    _logger.i('Broadcasting skip prev');
    await broadcast(message);
  }

  /// Broadcast a volume control command to all slaves.
  Future<void> broadcastVolume({required double volume}) async {
    final message = ProtocolMessage.volumeControl(volume: volume);
    _logger.i('Broadcasting volume: $volume');
    await broadcast(message);
  }

  /// Broadcast a playlist update to all slaves.
  Future<void> broadcastPlaylistUpdate({
    required List<Map<String, dynamic>> tracks,
    required int currentIndex,
    String? repeatMode,
    bool? isShuffled,
  }) async {
    final message = ProtocolMessage.playlistUpdate(
      tracks: tracks,
      currentIndex: currentIndex,
      repeatMode: repeatMode,
      isShuffled: isShuffled,
    );
    _logger.i('Broadcasting playlist update: ${tracks.length} tracks, index=$currentIndex, repeat=$repeatMode, shuffled=$isShuffled');
    await broadcast(message);
  }

  /// Send a message to a specific slave.
  Future<void> sendToSlave(String deviceId, ProtocolMessage message) async {
    final slave = _slaves[deviceId];
    if (slave == null) {
      _logger.w('Cannot send to unknown device: $deviceId');
      return;
    }
    try {
      slave.socket.add(message.encode());
    } catch (e) {
      _logger.e('Error sending to $deviceId: $e');
    }
  }

  /// Broadcast binary data to all connected slaves.
  /// Used for file transfer binary frames (QWEN-P1-2 fix).
  Future<void> broadcastBinary(List<int> data) async {
    final slavesCopy = [..._slaves.values];
    for (final slave in slavesCopy) {
      try {
        slave.socket.add(data);
      } catch (e) {
        _logger.e('Error sending binary to ${slave.deviceName}: $e');
      }
    }
  }

  /// Send binary data to a specific slave.
  Future<void> sendBinaryToSlave(String deviceId, List<int> data) async {
    final slave = _slaves[deviceId];
    if (slave == null) {
      _logger.w('Cannot send binary to unknown device: $deviceId');
      return;
    }
    try {
      slave.socket.add(data);
    } catch (e) {
      _logger.e('Error sending binary to $deviceId: $e');
    }
  }

  // ── Internal ──

  void _handleRequest(HttpRequest request) async {
    if (request.uri.path != AppConstants.webSocketPath) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _logger.i('New WebSocket connection from ${request.connectionInfo?.remoteAddress}');

      socket.listen(
        (data) => _handleMessage(socket, data),
        onDone: () => _handleDisconnect(socket),
        onError: (error) => _handleError(socket, error),
      );
    } catch (e) {
      _logger.e('WebSocket upgrade failed: $e');
    }
  }

  void _handleMessage(WebSocket socket, dynamic data) {
    try {
      if (data is String) {
        // Handle JSON message
        final message = ProtocolMessage.decode(data);

        switch (message.type) {
          case MessageType.join:
            _handleJoin(socket, message);
            break;
          case MessageType.syncRequest:
            _handleSyncRequest(socket, message);
            break;
          case MessageType.heartbeatAck:
            _handleHeartbeatAck(socket, message);
            break;
          case MessageType.audioReady:
            _handleAudioReady(socket, message);
            break;
          case MessageType.disconnect:
            _handleDisconnectMessage(socket, message);
            break;
          case MessageType.guestPause:
            _handleGuestPause(socket, message);
            break;
          case MessageType.guestResume:
            _handleGuestResume(socket, message);
            break;
          default:
            _logger.w('Unhandled message type: ${message.type}');
        }
      } else if (data is List<int>) {
        // Handle binary data (file transfer chunks)
        _handleBinaryMessage(socket, data);
      } else {
        _logger.w('Received unknown message type: ${data.runtimeType}');
      }
    } catch (e) {
      _logger.e('Error handling message: $e');
    }
  }

  /// Handle binary messages (file transfer chunks).
  void _handleBinaryMessage(WebSocket socket, List<int> data) {
    // Binary chunks are handled by the file transfer service
    // Add to event stream for processing
    _eventController.add(ServerEvent(
      type: ServerEventType.messageReceived,
      deviceId: _getDeviceIdForSocket(socket) ?? 'unknown',
      deviceName: 'unknown',
      data: data,
    ));
  }

  /// Get device ID for a socket.
  String? _getDeviceIdForSocket(WebSocket socket) {
    for (final entry in _slaves.entries) {
      if (entry.value.socket == socket) {
        return entry.key;
      }
    }
    return null;
  }

  void _handleJoin(WebSocket socket, ProtocolMessage message) {
    final deviceJson = message.payload['device'];
    if (deviceJson is! Map<String, dynamic>) {
      _logger.e('Invalid device payload in join message');
      socket.add(ProtocolMessage.reject(reason: 'Invalid join payload').encode());
      socket.close();
      return;
    }
    final device = DeviceInfo.fromJson(deviceJson);

    // Reject if session is full (HIGH-014 fix)
    final isReconnection = _slaves.containsKey(device.id);
    if (!isReconnection && _slaves.length >= AppConstants.maxSlaves) {
      _logger.w('Rejecting ${device.name}: session full (${_slaves.length}/${AppConstants.maxSlaves})');
      socket.add(ProtocolMessage.reject(reason: 'Session is full (max ${AppConstants.maxSlaves} devices)').encode());
      socket.close();
      return;
    }

    _logger.i('Device ${isReconnection ? "reconnecting" : "joining"}: ${device.name} (${device.id})');
    _slaves[device.id] = ConnectedSlave(
      deviceId: device.id,
      deviceName: device.name,
      socket: socket,
      connectedAt: DateTime.now(),
    );

    // Send welcome
    final welcome = ProtocolMessage.welcome(
      sessionId: sessionId,
      role: 'slave',
    );
    socket.add(welcome.encode());

    _eventController.add(ServerEvent(
      type: ServerEventType.deviceConnected,
      deviceId: device.id,
      deviceName: device.name,
    ));
  }

  void _handleSyncRequest(WebSocket socket, ProtocolMessage message) {
    final t2 = DateTime.now().millisecondsSinceEpoch;
    final t1 = message.timestampMs;
    final t3 = DateTime.now().millisecondsSinceEpoch;

    final response = ProtocolMessage.syncResponse(t1: t1, t2: t2, t3: t3);
    socket.add(response.encode());
  }

  void _handleHeartbeatAck(WebSocket socket, ProtocolMessage message) {
    for (final slave in _slaves.values) {
      if (slave.socket == socket) {
        slave.lastHeartbeat = DateTime.now();
        break;
      }
    }
  }

  void _handleAudioReady(WebSocket socket, ProtocolMessage message) {
    for (final slave in _slaves.values) {
      if (slave.socket == socket) {
        slave.isSynced = true;
        _logger.i('Device ${slave.deviceName} is ready');
        _eventController.add(ServerEvent(
          type: ServerEventType.deviceReady,
          deviceId: slave.deviceId,
          deviceName: slave.deviceName,
        ));
        break;
      }
    }
  }

  void _handleDisconnectMessage(WebSocket socket, ProtocolMessage message) {
    _removeSlaveBySocket(socket);
  }

  void _handleGuestPause(WebSocket socket, ProtocolMessage message) {
    final deviceId = _getDeviceIdForSocket(socket) ?? 'unknown';
    final slave = _slaves[deviceId];
    final deviceName = slave?.deviceName ?? 'unknown';
    final positionMs = (message.payload['position_ms'] as num?)?.toInt() ?? 0;
    _logger.i('Guest $deviceName paused at ${positionMs}ms');
    // HIGH-009 fix: Use dedicated event type instead of generic messageReceived
    _eventController.add(ServerEvent(
      type: ServerEventType.guestPaused,
      deviceId: deviceId,
      deviceName: deviceName,
      data: positionMs,
    ));
  }

  void _handleGuestResume(WebSocket socket, ProtocolMessage message) {
    final deviceId = _getDeviceIdForSocket(socket) ?? 'unknown';
    final slave = _slaves[deviceId];
    final deviceName = slave?.deviceName ?? 'unknown';
    _logger.i('Guest $deviceName resumed playback');
    // HIGH-009 fix: Use dedicated event type instead of generic messageReceived
    _eventController.add(ServerEvent(
      type: ServerEventType.guestResumed,
      deviceId: deviceId,
      deviceName: deviceName,
    ));
  }

  void _handleDisconnect(WebSocket socket) {
    _logger.i('WebSocket disconnected');
    _removeSlaveBySocket(socket);
  }

  void _handleError(WebSocket socket, dynamic error) {
    _logger.e('WebSocket error: $error');
    _removeSlaveBySocket(socket);
  }

  void _removeSlaveBySocket(WebSocket socket) {
    String? removedId;
    String? removedName;

    _slaves.removeWhere((id, slave) {
      if (slave.socket == socket) {
        removedId = id;
        removedName = slave.deviceName;
        return true;
      }
      return false;
    });

    if (removedId != null) {
      _logger.i('Device removed: $removedName ($removedId)');
      _eventController.add(ServerEvent(
        type: ServerEventType.deviceDisconnected,
        deviceId: removedId!,
        deviceName: removedName ?? 'Unknown',
      ));
    }
  }

  void _checkHeartbeats() {
    final now = DateTime.now();
    final timedOut = <String>[];

    for (final entry in _slaves.entries) {
      final elapsed = now.difference(entry.value.lastHeartbeat).inSeconds;
      if (elapsed > _heartbeatTimeoutSeconds) {
        timedOut.add(entry.key);
      }
    }

    for (final deviceId in timedOut) {
      final slave = _slaves[deviceId];
      if (slave != null) {
        _logger.w('Heartbeat timeout for ${slave.deviceName}');
        // Close the socket before removing
        try {
          slave.socket.close();
        } catch (e) {
          _logger.d('Socket close error: $e');
        }
        _slaves.remove(deviceId);
        _eventController.add(ServerEvent(
          type: ServerEventType.deviceDisconnected,
          deviceId: deviceId,
          deviceName: slave.deviceName,
          reason: 'heartbeat_timeout',
        ));
      }
    }

    // Send heartbeat to remaining slaves
    final heartbeat = ProtocolMessage.heartbeat();
    for (final slave in _slaves.values) {
      try {
        slave.socket.add(heartbeat.encode());
      } catch (e) {
        _logger.d('Heartbeat send error to ${slave.deviceName}: $e');
      }
    }
  }

  /// Broadcast a message to all connected slaves.
  Future<void> broadcast(ProtocolMessage message) async {
    final encoded = message.encode();
    // Create a copy to avoid ConcurrentModificationError if slaves are removed during iteration
    final slaves = [..._slaves.values];
    for (final slave in slaves) {
      try {
        slave.socket.add(encoded);
      } catch (e) {
        _logger.e('Broadcast error to ${slave.deviceName}: $e');
      }
    }
  }

  Future<void> dispose() async {
    await stop();
    await _eventController.close();
    clockSync.dispose();
  }
}

// ── Server Events ──

enum ServerEventType {
  deviceConnected,
  deviceDisconnected,
  deviceReady,
  messageReceived,
  guestPaused,    // HIGH-009 fix
  guestResumed,   // HIGH-009 fix
  error,
}

class ServerEvent {
  final ServerEventType type;
  final String deviceId;
  final String deviceName;
  final String? reason;
  final dynamic data; // Binary data for file transfer chunks

  const ServerEvent({
    required this.type,
    required this.deviceId,
    required this.deviceName,
    this.reason,
    this.data,
  });
}
