import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:logger/logger.dart';
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
  static const int _heartbeatIntervalSeconds = 5;
  static const int _heartbeatTimeoutSeconds = 15;

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
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _logger.i('WebSocket server started on port $port');

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

  /// Broadcast a play command to all slaves.
  Future<void> broadcastPlay({
    required String trackSource,
    required AudioSourceType sourceType,
    int delayMs = 2000,
    int seekPositionMs = 0,
  }) async {
    final startAtMs = clockSync.syncedTimeMs + delayMs;

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

  // ── Internal ──

  void _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/musync') {
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
      final message = ProtocolMessage.decode(data as String);

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
        default:
          _logger.w('Unhandled message type: ${message.type}');
      }
    } catch (e) {
      _logger.e('Error handling message: $e');
    }
  }

  void _handleJoin(WebSocket socket, ProtocolMessage message) {
    final deviceJson = message.payload['device'] as Map<String, dynamic>;
    final device = DeviceInfo.fromJson(deviceJson);

    if (_slaves.containsKey(device.id)) {
      // Reconnection
      _logger.i('Device reconnecting: ${device.name} (${device.id})');
      _slaves[device.id] = ConnectedSlave(
        deviceId: device.id,
        deviceName: device.name,
        socket: socket,
        connectedAt: DateTime.now(),
      );
    } else {
      _logger.i('Device joining: ${device.name} (${device.id})');
      _slaves[device.id] = ConnectedSlave(
        deviceId: device.id,
        deviceName: device.name,
        socket: socket,
        connectedAt: DateTime.now(),
      );
    }

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

    // Find which slave this is and update their offset
    for (final slave in _slaves.values) {
      if (slave.socket == socket) {
        // The slave will calculate the offset, but we can track it here too
        break;
      }
    }
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
      } catch (_) {}
    }
  }

  /// Broadcast a message to all connected slaves.
  Future<void> broadcast(ProtocolMessage message) async {
    final encoded = message.encode();
    for (final slave in _slaves.values) {
      try {
        slave.socket.add(encoded);
      } catch (e) {
        _logger.e('Broadcast error to ${slave.deviceName}: $e');
      }
    }
  }

  void dispose() {
    stop();
    _eventController.close();
    clockSync.dispose();
  }
}

// ── Server Events ──

enum ServerEventType {
  deviceConnected,
  deviceDisconnected,
  deviceReady,
  error,
}

class ServerEvent {
  final ServerEventType type;
  final String deviceId;
  final String deviceName;
  final String? reason;

  const ServerEvent({
    required this.type,
    required this.deviceId,
    required this.deviceName,
    this.reason,
  });
}
