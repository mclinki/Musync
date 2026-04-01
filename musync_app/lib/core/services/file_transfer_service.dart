import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../app_constants.dart';
import '../models/protocol_message.dart';
import '../network/websocket_server.dart';
import '../utils/format.dart';

/// Handles file transfer between host and slaves.
///
/// When the host wants to play a local file:
/// 1. Host sends fileTransferStart with file metadata
/// 2. Host sends fileTransferChunk for each chunk (base64 encoded)
/// 3. Host sends fileTransferEnd
/// 4. Slave sends fileTransferAck when file is saved
///
/// Files are stored in a temporary directory that is cleared on app restart.
class FileTransferService {
  final Logger _logger;
  
  // Temporary directory for received files
  Directory? _tempDir;
  
  // Active transfers (slave side)
  final Map<String, _IncomingTransfer> _incomingTransfers = {};
  
  // Stream controller for transfer progress
  final StreamController<TransferProgress> _progressController = 
      StreamController.broadcast();

  // Timeout timer for incomplete transfers
  Timer? _cleanupTimer;
  static const _transferTimeout = Duration(seconds: 30);

  FileTransferService({Logger? logger}) : _logger = logger ?? Logger();

  Stream<TransferProgress> get progressStream => _progressController.stream;

  /// Initialize the service and clean up old files.
  Future<void> initialize() async {
    _tempDir = await getTemporaryDirectory();
    final musyncDir = Directory('${_tempDir!.path}/musync_cache');
    
    if (await musyncDir.exists()) {
      _logger.i('Cleaning up old cache files...');
      await musyncDir.delete(recursive: true);
    }
    
    await musyncDir.create(recursive: true);
    _tempDir = musyncDir;
    _logger.i('File transfer cache: ${_tempDir!.path}');

    // Start cleanup timer for incomplete transfers
    _startCleanupTimer();
  }

  /// Start timer to clean up incomplete transfers.
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleTransfers();
    });
  }

  /// Clean up transfers that have been inactive for too long.
  void _cleanupStaleTransfers() {
    final now = DateTime.now();
    final staleKeys = <String>[];

    for (final entry in _incomingTransfers.entries) {
      final transfer = entry.value;
      final elapsed = now.difference(transfer.startedAt);
      if (elapsed > _transferTimeout) {
        _logger.w('Cleaning up stale transfer: ${transfer.fileName} (${elapsed.inSeconds}s)');
        staleKeys.add(entry.key);
      }
    }

    for (final key in staleKeys) {
      _incomingTransfers.remove(key);
    }
  }

  /// Get the cache directory path.
  String? get cachePath => _tempDir?.path;

  /// Send a file to all connected slaves using binary frames.
  /// Returns true when all chunks have been sent (does NOT wait for ACKs).
  /// Uses binary WebSocket frames instead of Base64 encoding (QWEN-P1-2 fix).
  Future<bool> sendFile({
    required String filePath,
    required WebSocketServer server,
    Duration timeout = const Duration(seconds: AppConstants.fileTransferTimeoutSeconds),
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _logger.e('File not found: $filePath');
      return false;
    }

    final fileName = filePath.split('/').last.split('\\').last;
    final fileSize = await file.length();
    const chunkSize = AppConstants.fileChunkSizeBytes;
    final totalChunks = (fileSize / chunkSize).ceil();

    _logger.i('=== STARTING FILE TRANSFER (binary) ===');
    _logger.i('fileName: $fileName');
    _logger.i('fileSize: ${formatBytes(fileSize)}');
    _logger.i('totalChunks: $totalChunks');
    _logger.i('chunkSize: ${formatBytes(chunkSize)}');

    // Notify slaves about incoming file
    final startMsg = ProtocolMessage.fileTransferStart(
      fileName: fileName,
      fileSizeBytes: fileSize,
      totalChunks: totalChunks,
      chunkSizeBytes: chunkSize,
    );
    server.broadcast(startMsg);
    _logger.d('Sent fileTransferStart message');

    // Wait a bit for slaves to prepare
    await Future.delayed(const Duration(milliseconds: 500));

    // Send chunks as binary frames - stream from disk
    final reader = file.openRead();
    int offset = 0;
    int chunkIndex = 0;
    final buffer = <int>[];

    await for (final data in reader) {
      buffer.addAll(data);

      while (buffer.length >= chunkSize) {
        final chunk = buffer.sublist(0, chunkSize);
        buffer.removeRange(0, chunkSize);

        // Send binary frame with chunk header
        final binaryFrame = _buildBinaryChunkFrame(chunkIndex, chunk);
        await server.broadcastBinary(binaryFrame);

        offset += chunkSize;
        chunkIndex++;
        _logger.d('Sent chunk $chunkIndex/$totalChunks (${formatBytes(offset)}/${formatBytes(fileSize)})');

        // Report progress
        _progressController.add(TransferProgress(
          fileName: fileName,
          bytesTransferred: offset,
          totalBytes: fileSize,
          isIncoming: false,
        ));

        // Small delay to avoid flooding
        if (chunkIndex % AppConstants.interChunkDelayInterval == 0) {
          await Future.delayed(const Duration(milliseconds: AppConstants.interChunkDelayMs));
        }
      }
    }

    // Send remaining bytes as last chunk
    if (buffer.isNotEmpty) {
      final binaryFrame = _buildBinaryChunkFrame(chunkIndex, buffer);
      await server.broadcastBinary(binaryFrame);
      offset += buffer.length;
      chunkIndex++;
      _logger.d('Sent final chunk $chunkIndex/$totalChunks (${formatBytes(offset)}/${formatBytes(fileSize)})');

      _progressController.add(TransferProgress(
        fileName: fileName,
        bytesTransferred: offset,
        totalBytes: fileSize,
        isIncoming: false,
      ));

      // Delay after final chunk for consistency
      await Future.delayed(const Duration(milliseconds: AppConstants.interChunkDelayMs));
    }

    // Signal end of transfer
    final endMsg = ProtocolMessage.fileTransferEnd();
    server.broadcast(endMsg);

    _logger.i('=== FILE TRANSFER COMPLETE ===');
    _logger.i('File sent: $fileName ($totalChunks chunks, ${formatBytes(fileSize)})');
    _logger.i('Slaves count at transfer end: ${server.slaveCount}');
    return true;
  }

  /// Build a binary frame for a file chunk.
  /// Format: [4 bytes chunkIndex][4 bytes dataLength][data...]
  List<int> _buildBinaryChunkFrame(int chunkIndex, List<int> data) {
    final frame = BytesBuilder();
    // Chunk index (4 bytes, big-endian)
    frame.addByte((chunkIndex >> 24) & 0xFF);
    frame.addByte((chunkIndex >> 16) & 0xFF);
    frame.addByte((chunkIndex >> 8) & 0xFF);
    frame.addByte(chunkIndex & 0xFF);
    // Data length (4 bytes, big-endian)
    final dataLength = data.length;
    frame.addByte((dataLength >> 24) & 0xFF);
    frame.addByte((dataLength >> 16) & 0xFF);
    frame.addByte((dataLength >> 8) & 0xFF);
    frame.addByte(dataLength & 0xFF);
    // Data
    frame.add(data);
    return frame.toBytes();
  }

  /// Parse a binary chunk frame.
  /// Returns (chunkIndex, data) or null if invalid.
  static (int, List<int>)? parseBinaryChunkFrame(List<int> frame) {
    if (frame.length < 8) return null;
    final chunkIndex = (frame[0] << 24) | (frame[1] << 16) | (frame[2] << 8) | frame[3];
    final dataLength = (frame[4] << 24) | (frame[5] << 16) | (frame[6] << 8) | frame[7];
    if (frame.length < 8 + dataLength) return null;
    final data = frame.sublist(8, 8 + dataLength);
    return (chunkIndex, data);
  }

  /// Handle incoming file transfer messages (slave side).
  /// Returns the local file path when transfer is complete, or null on error.
  Future<String?> handleIncomingMessage(ProtocolMessage message) async {
    switch (message.type) {
      case MessageType.fileTransferStart:
        return _handleTransferStart(message);
      case MessageType.fileTransferChunk:
        return _handleTransferChunk(message);
      case MessageType.fileTransferEnd:
        return _handleTransferEnd(message);
      default:
        return null;
    }
  }

  /// Handle incoming binary file transfer chunk (slave side).
  /// Returns the local file path when transfer is complete, or null on error.
  Future<String?> handleBinaryChunk(List<int> binaryData) async {
    final parsed = parseBinaryChunkFrame(binaryData);
    if (parsed == null) {
      _logger.w('Invalid binary chunk frame');
      return null;
    }

    final (chunkIndex, data) = parsed;
    return _handleBinaryTransferChunk(chunkIndex, data);
  }

  /// Handle binary transfer chunk.
  Future<String?> _handleBinaryTransferChunk(int chunkIndex, List<int> data) async {
    if (_incomingTransfers.isEmpty) {
      _logger.w('Received binary chunk but no active transfer!');
      return null;
    }

    if (chunkIndex < 0) {
      _logger.w('Invalid chunk index: $chunkIndex');
      return null;
    }

    // Find the transfer this chunk belongs to (most recent if ambiguous)
    final transfer = _incomingTransfers.values.last;

    // Verify chunk order - insert at correct index
    if (chunkIndex < transfer.totalChunks) {
      // Ensure the chunks list has enough capacity
      while (transfer.chunks.length <= chunkIndex) {
        transfer.chunks.add(Uint8List(0));
      }
      transfer.chunks[chunkIndex] = Uint8List.fromList(data);
    } else {
      _logger.w('Received chunk $chunkIndex but totalChunks is ${transfer.totalChunks}');
    }

    final receivedCount = transfer.chunks.where((c) => c.isNotEmpty).length;
    _logger.d('Received binary chunk $chunkIndex, total chunks: $receivedCount/${transfer.totalChunks}');

    // Report progress
    _progressController.add(TransferProgress(
      fileName: transfer.fileName,
      bytesTransferred: transfer.chunks.fold<int>(0, (sum, chunk) => sum + chunk.length),
      totalBytes: transfer.fileSize,
      isIncoming: true,
    ));

    return null;
  }

  Future<String?> _handleTransferStart(ProtocolMessage message) async {
    final fileName = message.payload['file_name'] as String? ?? 'unknown';
    final fileSize = (message.payload['file_size_bytes'] as num?)?.toInt() ?? 0;
    final totalChunks = (message.payload['total_chunks'] as num?)?.toInt() ?? 0;

    if (fileName == 'unknown' || fileSize == 0 || totalChunks == 0) {
      _logger.w('Invalid fileTransferStart payload: ${message.payload}');
      return null;
    }

    _logger.i('=== FILE TRANSFER START ===');
    _logger.i('fileName: $fileName');
    _logger.i('fileSize: $fileSize bytes');
    _logger.i('totalChunks: $totalChunks');

    _incomingTransfers[fileName] = _IncomingTransfer(
      fileName: fileName,
      fileSize: fileSize,
      totalChunks: totalChunks,
      chunks: [],
    );

    return null;
  }

  Future<String?> _handleTransferChunk(ProtocolMessage message) async {
    // Find active transfer by filename (supports concurrent transfers)
    if (_incomingTransfers.isEmpty) {
      _logger.w('Received chunk but no active transfer!');
      return null;
    }
    
    final chunkIndex = (message.payload['chunk_index'] as num?)?.toInt() ?? -1;
    final base64Data = message.payload['data'] as String? ?? '';

    if (chunkIndex < 0 || base64Data.isEmpty) {
      _logger.w('Invalid fileTransferChunk payload: ${message.payload}');
      return null;
    }

    // Find the transfer this chunk belongs to (most recent if ambiguous)
    final transfer = _incomingTransfers.values.last;

    final bytes = base64Decode(base64Data);

    // Verify chunk order - insert at correct index
    if (chunkIndex < transfer.totalChunks) {
      // Ensure the chunks list has enough capacity
      while (transfer.chunks.length <= chunkIndex) {
        transfer.chunks.add(Uint8List(0));
      }
      transfer.chunks[chunkIndex] = bytes;
    } else {
      _logger.w('Received chunk $chunkIndex but totalChunks is ${transfer.totalChunks}');
    }

    final receivedCount = transfer.chunks.where((c) => c.isNotEmpty).length;
    _logger.d('Received chunk $chunkIndex, total chunks: $receivedCount/${transfer.totalChunks}');
    
    // Report progress
    _progressController.add(TransferProgress(
      fileName: transfer.fileName,
      bytesTransferred: transfer.chunks.fold<int>(0, (sum, chunk) => sum + chunk.length),
      totalBytes: transfer.fileSize,
      isIncoming: true,
    ));

    return null;
  }

  Future<String?> _handleTransferEnd(ProtocolMessage message) async {
    if (_incomingTransfers.isEmpty) {
      _logger.w('No active transfer to complete');
      return null;
    }

    if (_tempDir == null) {
      _logger.e('Cannot save file: temp dir not initialized');
      _incomingTransfers.clear();
      return null;
    }
    
    final transfer = _incomingTransfers.values.first;
    _logger.i('Completing transfer for ${transfer.fileName}, ${transfer.chunks.length} chunks received');
    
    // Combine all chunks
    final allBytes = BytesBuilder();
    for (final chunk in transfer.chunks) {
      allBytes.add(chunk);
    }

    // Save to temp directory
    final filePath = '${_tempDir!.path}/${transfer.fileName}';
    final file = File(filePath);
    await file.writeAsBytes(allBytes.toBytes());

    // Verify file was written
    if (await file.exists()) {
      final savedSize = await file.length();
      _logger.i('File received and saved: $filePath (${formatBytes(savedSize)}, expected ${formatBytes(transfer.fileSize)})');
    } else {
      _logger.e('ERROR: File was not written to disk!');
    }

    // Clean up transfer state
    _incomingTransfers.remove(transfer.fileName);

    return filePath;
  }

  /// Clean up all cached files.
  Future<void> cleanup() async {
    if (_tempDir != null && await _tempDir!.exists()) {
      await _tempDir!.delete(recursive: true);
      await _tempDir!.create(recursive: true);
      _logger.i('Cache cleaned up');
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await _progressController.close();
  }
}

/// Tracks an incoming file transfer.
class _IncomingTransfer {
  final String fileName;
  final int fileSize;
  final int totalChunks;
  final List<Uint8List> chunks;
  final DateTime startedAt;

  _IncomingTransfer({
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    required this.chunks,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
}

/// Progress information for a file transfer.
class TransferProgress {
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final bool isIncoming;

  TransferProgress({
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.isIncoming,
  });

  double get percentage => totalBytes > 0 ? bytesTransferred / totalBytes : 0;
}
