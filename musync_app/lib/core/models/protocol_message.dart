import 'dart:convert';
import 'device_info.dart';
import 'audio_session.dart';

/// Protocol messages exchanged between host and slaves over WebSocket.
enum MessageType {
  // Connection
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
  seek,
  skipNext,
  skipPrev,

  // Audio streaming
  audioReady,

  // File transfer
  fileTransferStart,  // Announce file transfer (filename, size, totalChunks)
  fileTransferChunk,  // Send a chunk of the file
  fileTransferEnd,    // File transfer complete
  fileTransferAck,    // Slave confirms file received

  // Playlist sync
  playlistUpdate,

  // Session
  heartbeat,
  heartbeatAck,
  error,

  // APK transfer
  apkTransferOffer,   // Host offers to send APK (with version info)
  apkTransferAccept,  // Slave accepts APK transfer
  apkTransferDecline, // Slave declines APK transfer

  // Guest playback state
  guestPause,         // Guest notifies host that it paused locally
  guestResume,        // Guest notifies host that it resumed locally

  // Volume control
  volumeControl,      // Host broadcasts volume to slaves
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
    try {
      // Validate message size (1MB max)
      if (data.length > 1024 * 1024) {
        return ProtocolMessage(
          type: MessageType.error,
          payload: {'message': 'Message too large'},
        );
      }
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        return ProtocolMessage(type: MessageType.error, payload: {'message': 'Invalid message format'});
      }
      final map = decoded;

      // Validate 'type' field
      final typeStr = map['type'];
      if (typeStr is! String) {
        return ProtocolMessage(type: MessageType.error, payload: {'message': 'Missing message type'});
      }

      final rawPayload = map['payload'];
      return ProtocolMessage(
        type: MessageType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => MessageType.error,
        ),
        payload: rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : {},
        timestampMs: (map['ts'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      // MED-004: Include truncated raw data for debugging
      final preview = data.length > 100 ? '${data.substring(0, 100)}...' : data;
      return ProtocolMessage(type: MessageType.error, payload: {
        'message': 'Decode error: $e',
        'raw_preview': preview,
      });
    }
  }

  // ── Factory constructors for each message type ──

  factory ProtocolMessage.join({
    required DeviceInfo device,
    String? sessionPin,
  }) {
    return ProtocolMessage(
      type: MessageType.join,
      payload: {
        'device': device.toJson(),
        if (sessionPin != null) 'session_pin': sessionPin,
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

  factory ProtocolMessage.skipNext() {
    return ProtocolMessage(type: MessageType.skipNext);
  }

  factory ProtocolMessage.skipPrev() {
    return ProtocolMessage(type: MessageType.skipPrev);
  }

  factory ProtocolMessage.playlistUpdate({
    required List<Map<String, dynamic>> tracks,
    required int currentIndex,
    String? repeatMode,
    bool? isShuffled,
  }) {
    return ProtocolMessage(
      type: MessageType.playlistUpdate,
      payload: {
        'tracks': tracks,
        'current_index': currentIndex,
        if (repeatMode != null) 'repeat_mode': repeatMode,
        if (isShuffled != null) 'is_shuffled': isShuffled,
      },
    );
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
    String? transferId,
  }) {
    return ProtocolMessage(
      type: MessageType.fileTransferStart,
      payload: {
        'file_name': fileName,
        'file_size_bytes': fileSizeBytes,
        'total_chunks': totalChunks,
        'chunk_size_bytes': chunkSizeBytes,
        if (transferId != null) 'transfer_id': transferId,
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

  // APK transfer messages
  factory ProtocolMessage.apkTransferOffer({
    required String version,
    required int fileSizeBytes,
  }) {
    return ProtocolMessage(
      type: MessageType.apkTransferOffer,
      payload: {
        'version': version,
        'file_size_bytes': fileSizeBytes,
      },
    );
  }

  factory ProtocolMessage.apkTransferAccept() {
    return ProtocolMessage(type: MessageType.apkTransferAccept);
  }

  factory ProtocolMessage.apkTransferDecline({String? reason}) {
    return ProtocolMessage(
      type: MessageType.apkTransferDecline,
      payload: {
        'reason': reason ?? 'Declined by user',
      },
    );
  }

  // Guest playback state
  factory ProtocolMessage.guestPause({required int positionMs}) {
    return ProtocolMessage(
      type: MessageType.guestPause,
      payload: {'position_ms': positionMs},
    );
  }

  factory ProtocolMessage.guestResume() {
    return ProtocolMessage(type: MessageType.guestResume);
  }

  // Volume control
  factory ProtocolMessage.volumeControl({required double volume}) {
    return ProtocolMessage(
      type: MessageType.volumeControl,
      payload: {'volume': volume},
    );
  }
}
