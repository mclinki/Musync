import 'dart:convert';
import 'device_info.dart';
import 'audio_session.dart';

/// Protocol messages exchanged between host and slaves over WebSocket.
enum MessageType {
  // Connection
  hello,
  join,
  welcome,
  reject,
  disconnect,

  // Clock sync
  syncRequest,
  syncResponse,
  clockAdjust,

  // Playback control
  prepare,  // Pre-load a track for faster playback
  play,
  pause,
  stop,
  seek,
  skipNext,
  skipPrev,

  // Audio streaming
  audioChunk,
  audioReady,

  // File transfer
  fileTransferStart,  // Announce file transfer (filename, size, totalChunks)
  fileTransferChunk,  // Send a chunk of the file
  fileTransferEnd,    // File transfer complete
  fileTransferAck,    // Slave confirms file received

  // Session
  heartbeat,
  heartbeatAck,
  deviceUpdate,
  error,
}

/// A message in the MusyncMIMO protocol.
class ProtocolMessage {
  final MessageType type;
  final Map<String, dynamic> payload;
  final int timestampMs;

  ProtocolMessage({
    required this.type,
    Map<String, dynamic>? payload,
    int? timestampMs,
  })  : payload = payload ?? {},
        timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  String encode() {
    return jsonEncode({
      'type': type.name,
      'payload': payload,
      'ts': timestampMs,
    });
  }

  factory ProtocolMessage.decode(String data) {
    final map = jsonDecode(data) as Map<String, dynamic>;
    return ProtocolMessage(
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.error,
      ),
      payload: map['payload'] as Map<String, dynamic>? ?? {},
      timestampMs: map['ts'] as int? ?? 0,
    );
  }

  // ── Factory constructors for each message type ──

  factory ProtocolMessage.hello({
    required String sessionId,
    required DeviceInfo device,
  }) {
    return ProtocolMessage(
      type: MessageType.hello,
      payload: {
        'session_id': sessionId,
        'device': device.toJson(),
      },
    );
  }

  factory ProtocolMessage.join({
    required DeviceInfo device,
  }) {
    return ProtocolMessage(
      type: MessageType.join,
      payload: {
        'device': device.toJson(),
      },
    );
  }

  factory ProtocolMessage.welcome({
    required String sessionId,
    required String role,
  }) {
    return ProtocolMessage(
      type: MessageType.welcome,
      payload: {
        'session_id': sessionId,
        'role': role,
      },
    );
  }

  factory ProtocolMessage.reject({required String reason}) {
    return ProtocolMessage(
      type: MessageType.reject,
      payload: {'reason': reason},
    );
  }

  // Clock sync
  factory ProtocolMessage.syncRequest() {
    return ProtocolMessage(type: MessageType.syncRequest);
  }

  factory ProtocolMessage.syncResponse({
    required int t1,
    required int t2,
    required int t3,
  }) {
    return ProtocolMessage(
      type: MessageType.syncResponse,
      payload: {
        't1': t1,
        't2': t2,
        't3': t3,
      },
    );
  }

  factory ProtocolMessage.clockAdjust({
    required double offsetMs,
    required double driftPpm,
  }) {
    return ProtocolMessage(
      type: MessageType.clockAdjust,
      payload: {
        'offset_ms': offsetMs,
        'drift_ppm': driftPpm,
      },
    );
  }

  // Playback
  factory ProtocolMessage.prepare({
    required String trackSource,
    required AudioSourceType sourceType,
  }) {
    return ProtocolMessage(
      type: MessageType.prepare,
      payload: {
        'track_source': trackSource,
        'source_type': sourceType.name,
      },
    );
  }

  factory ProtocolMessage.play({
    required int startAtMs,
    required String trackSource,
    required AudioSourceType sourceType,
    int? seekPositionMs,
  }) {
    return ProtocolMessage(
      type: MessageType.play,
      payload: {
        'start_at_ms': startAtMs,
        'track_source': trackSource,
        'source_type': sourceType.name,
        'seek_position_ms': seekPositionMs ?? 0,
      },
    );
  }

  factory ProtocolMessage.pause({required int positionMs}) {
    return ProtocolMessage(
      type: MessageType.pause,
      payload: {'position_ms': positionMs},
    );
  }

  factory ProtocolMessage.seek({required int positionMs}) {
    return ProtocolMessage(
      type: MessageType.seek,
      payload: {'position_ms': positionMs},
    );
  }

  factory ProtocolMessage.heartbeat() {
    return ProtocolMessage(type: MessageType.heartbeat);
  }

  factory ProtocolMessage.heartbeatAck() {
    return ProtocolMessage(type: MessageType.heartbeatAck);
  }

  factory ProtocolMessage.audioReady() {
    return ProtocolMessage(type: MessageType.audioReady);
  }

  factory ProtocolMessage.error({required String message}) {
    return ProtocolMessage(
      type: MessageType.error,
      payload: {'message': message},
    );
  }

  // File transfer messages
  factory ProtocolMessage.fileTransferStart({
    required String fileName,
    required int fileSizeBytes,
    required int totalChunks,
    required int chunkSizeBytes,
  }) {
    return ProtocolMessage(
      type: MessageType.fileTransferStart,
      payload: {
        'file_name': fileName,
        'file_size_bytes': fileSizeBytes,
        'total_chunks': totalChunks,
        'chunk_size_bytes': chunkSizeBytes,
      },
    );
  }

  factory ProtocolMessage.fileTransferChunk({
    required int chunkIndex,
    required String data, // Base64 encoded
  }) {
    return ProtocolMessage(
      type: MessageType.fileTransferChunk,
      payload: {
        'chunk_index': chunkIndex,
        'data': data,
      },
    );
  }

  factory ProtocolMessage.fileTransferEnd() {
    return ProtocolMessage(type: MessageType.fileTransferEnd);
  }

  factory ProtocolMessage.fileTransferAck() {
    return ProtocolMessage(type: MessageType.fileTransferAck);
  }
}
