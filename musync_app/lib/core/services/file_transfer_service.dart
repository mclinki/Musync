import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../models/protocol_message.dart';
import '../network/websocket_server.dart';

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
  }

  /// Get the cache directory path.
  String? get cachePath => _tempDir?.path;

  /// Send a file to all connected slaves.
  /// Returns a Future that completes when all slaves have acknowledged.
  Future<bool> sendFile({
    required String filePath,
    required WebSocketServer server,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _logger.e('File not found: $filePath');
      return false;
    }

    final fileName = filePath.split('/').last.split('\\').last;
    final fileSize = await file.length();
    const chunkSize = 64 * 1024; // 64KB chunks
    final totalChunks = (fileSize / chunkSize).ceil();

    _logger.i('=== STARTING FILE TRANSFER ===');
    _logger.i('fileName: $fileName');
    _logger.i('fileSize: ${_formatBytes(fileSize)}');
    _logger.i('totalChunks: $totalChunks');
    _logger.i('chunkSize: ${_formatBytes(chunkSize)}');

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

    // Send chunks
    final bytes = await file.readAsBytes();
    int offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      final base64Data = base64Encode(chunk);

      final chunkMsg = ProtocolMessage.fileTransferChunk(
        chunkIndex: i,
        data: base64Data,
      );
      server.broadcast(chunkMsg);

      offset = end;
      _logger.d('Sent chunk $i/$totalChunks (${_formatBytes(offset)}/${_formatBytes(fileSize)})');
      
      // Report progress
      _progressController.add(TransferProgress(
        fileName: fileName,
        bytesTransferred: offset,
        totalBytes: fileSize,
        isIncoming: false,
      ));

      // Small delay to avoid flooding - but make it faster
      if (i % 5 == 0) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    // Signal end of transfer
    final endMsg = ProtocolMessage.fileTransferEnd();
    server.broadcast(endMsg);

    _logger.i('=== FILE TRANSFER COMPLETE ===');
    _logger.i('File sent: $fileName');
    return true;
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

  Future<String?> _handleTransferStart(ProtocolMessage message) async {
    final fileName = message.payload['file_name'] as String;
    final fileSize = message.payload['file_size_bytes'] as int;
    final totalChunks = message.payload['total_chunks'] as int;

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
    // Find active transfer (assuming single file transfer at a time)
    if (_incomingTransfers.isEmpty) {
      _logger.w('Received chunk but no active transfer!');
      return null;
    }
    
    final transfer = _incomingTransfers.values.first;
    final chunkIndex = message.payload['chunk_index'] as int;
    final base64Data = message.payload['data'] as String;
    final bytes = base64Decode(base64Data);

    transfer.chunks.add(bytes);
    _logger.d('Received chunk $chunkIndex, total chunks: ${transfer.chunks.length}/${transfer.totalChunks}');
    
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
      _logger.i('File received and saved: $filePath (${_formatBytes(savedSize)}, expected ${_formatBytes(transfer.fileSize)})');
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
  void dispose() {
    _progressController.close();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Tracks an incoming file transfer.
class _IncomingTransfer {
  final String fileName;
  final int fileSize;
  final int totalChunks;
  final List<Uint8List> chunks;

  _IncomingTransfer({
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    required this.chunks,
  });
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
