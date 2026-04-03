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
/// 1. Host sends fileTransferStart with file metadata + transferId
/// 2. Host sends fileTransferChunk for each chunk (base64 encoded)
/// 3. Host sends fileTransferEnd
/// 4. Slave sends fileTransferAck when file is saved
///
/// Files are stored in a temporary directory that is cleared on app restart.
class FileTransferService {
  final Logger _logger;
  
  // Temporary directory for received files
  Directory? _tempDir;
  
  // Active transfers (slave side) — keyed by transferId (CRIT-003 fix)
  final Map<String, _IncomingTransfer> _incomingTransfers = {};
  
  // Current transfer ID for the active transfer (set by fileTransferStart)
  String? _activeTransferId;
  
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
      final transfer = _incomingTransfers[key];
      if (transfer != null) {
        // CRIT-008 fix: Close file handle before deleting partial file
        transfer.fileHandle?.close().catchError((e) {
          _logger.w('Failed to close stale file handle: $e');
        });
        if (_tempDir != null) {
          final partialFile = File('${_tempDir!.path}/${transfer.fileName}');
          if (partialFile.existsSync()) {
            partialFile.deleteSync();
            _logger.d('Deleted partial file: ${transfer.fileName}');
          }
        }
      }
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

    final fileName = extractFileName(filePath);
    final fileSize = await file.length();
    const chunkSize = AppConstants.fileChunkSizeBytes;
    final totalChunks = (fileSize / chunkSize).ceil();
    // Unique transfer ID for unambiguous chunk routing (CRIT-003 fix)
    final transferId = '${DateTime.now().millisecondsSinceEpoch}_$fileName';

    _logger.i('=== STARTING FILE TRANSFER (binary) ===');
    _logger.i('transferId: $transferId');
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
      transferId: transferId,
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
    // Use active transfer ID instead of .values.last (CRIT-003 fix)
    final transferId = _activeTransferId;
    if (transferId == null) {
      _logger.w('Received binary chunk but no active transfer!');
      return null;
    }

    final transfer = _incomingTransfers[transferId];
    if (transfer == null) {
      _logger.w('Received binary chunk for unknown transfer: $transferId');
      return null;
    }

    if (chunkIndex < 0) {
      _logger.w('Invalid chunk index: $chunkIndex');
      return null;
    }

    // CRIT-008 fix: Write chunk directly to disk via file handle instead of buffering in memory
    if (transfer.fileHandle != null) {
      try {
        await transfer.fileHandle!.setPosition(chunkIndex * AppConstants.fileChunkSizeBytes);
        await transfer.fileHandle!.writeFrom(data);
      } catch (e) {
        _logger.e('Failed to write chunk $chunkIndex to disk: $e');
        return null;
      }
    } else {
      // Fallback: buffer in memory (legacy mode for base64 transfers)
      while (transfer.chunks.length <= chunkIndex) {
        transfer.chunks.add(Uint8List(0));
      }
      transfer.chunks[chunkIndex] = Uint8List.fromList(data);
    }

    // Report progress
    final bytesTransferred = transfer.fileHandle != null
        ? (chunkIndex + 1) * AppConstants.fileChunkSizeBytes
        : transfer.chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);

    _progressController.add(TransferProgress(
      fileName: transfer.fileName,
      bytesTransferred: bytesTransferred.clamp(0, transfer.fileSize),
      totalBytes: transfer.fileSize,
      isIncoming: true,
    ));

    return null;
  }

  Future<String?> _handleTransferStart(ProtocolMessage message) async {
    final rawFileName = message.payload['file_name'] as String? ?? 'unknown';
    // HIGH-002 fix: Sanitize filename — strip all path components, keep only basename
    final fileName = rawFileName
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.\-]'), '_');
    final fileSize = (message.payload['file_size_bytes'] as num?)?.toInt() ?? 0;
    final totalChunks = (message.payload['total_chunks'] as num?)?.toInt() ?? 0;
    // Transfer ID for unambiguous chunk routing (CRIT-003 fix)
    final transferId = message.payload['transfer_id'] as String? ?? fileName;

    if (fileName == 'unknown' || fileName.isEmpty || fileSize == 0 || totalChunks == 0) {
      _logger.w('Invalid fileTransferStart payload: ${message.payload}');
      return null;
    }

    // HIGH-003 fix: Reject files exceeding max size
    if (fileSize > AppConstants.maxFileSizeBytes) {
      _logger.w('File too large: ${formatBytes(fileSize)} (max: ${formatBytes(AppConstants.maxFileSizeBytes)})');
      return null;
    }

    _logger.i('=== FILE TRANSFER START ===');
    _logger.i('transferId: $transferId');
    _logger.i('fileName: $fileName');
    _logger.i('fileSize: $fileSize bytes');
    _logger.i('totalChunks: $totalChunks');

    if (_tempDir == null) {
      _logger.e('Cannot start transfer: temp dir not initialized');
      return null;
    }

    // CRIT-008 fix: Open file handle for streaming writes instead of buffering in memory
    final filePath = '${_tempDir!.path}/$fileName';
    RandomAccessFile? fileHandle;
    try {
      fileHandle = await File(filePath).open(mode: FileMode.write);
    } catch (e) {
      _logger.e('Failed to open file for writing: $e');
      return null;
    }

    _activeTransferId = transferId;
    _incomingTransfers[transferId] = _IncomingTransfer(
      fileName: fileName,
      fileSize: fileSize,
      totalChunks: totalChunks,
      fileHandle: fileHandle,
    );

    return null;
  }

  Future<String?> _handleTransferChunk(ProtocolMessage message) async {
    // Use active transfer ID instead of .values.last (CRIT-003 fix)
    final transferId = _activeTransferId;
    if (transferId == null) {
      _logger.w('Received chunk but no active transfer!');
      return null;
    }

    final transfer = _incomingTransfers[transferId];
    if (transfer == null) {
      _logger.w('Received chunk for unknown transfer: $transferId');
      return null;
    }
    
    final chunkIndex = (message.payload['chunk_index'] as num?)?.toInt() ?? -1;
    final base64Data = message.payload['data'] as String? ?? '';

    if (chunkIndex < 0 || base64Data.isEmpty) {
      _logger.w('Invalid fileTransferChunk payload: ${message.payload}');
      return null;
    }

    final bytes = base64Decode(base64Data);

    // CRIT-008 fix: Write directly to disk if file handle is available
    if (transfer.fileHandle != null) {
      try {
        await transfer.fileHandle!.setPosition(chunkIndex * AppConstants.fileChunkSizeBytes);
        await transfer.fileHandle!.writeFrom(bytes);
      } catch (e) {
        _logger.e('Failed to write base64 chunk $chunkIndex to disk: $e');
        return null;
      }
    } else {
      // Fallback: buffer in memory
      while (transfer.chunks.length <= chunkIndex) {
        transfer.chunks.add(Uint8List(0));
      }
      transfer.chunks[chunkIndex] = bytes;
    }

    // Report progress
    final bytesTransferred = transfer.fileHandle != null
        ? (chunkIndex + 1) * AppConstants.fileChunkSizeBytes
        : transfer.chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);

    _progressController.add(TransferProgress(
      fileName: transfer.fileName,
      bytesTransferred: bytesTransferred.clamp(0, transfer.fileSize),
      totalBytes: transfer.fileSize,
      isIncoming: true,
    ));

    return null;
  }

  Future<String?> _handleTransferEnd(ProtocolMessage message) async {
    // Use active transfer ID instead of .values.first (CRIT-003 fix)
    final transferId = _activeTransferId;
    if (transferId == null) {
      _logger.w('No active transfer to complete');
      return null;
    }

    final transfer = _incomingTransfers[transferId];
    if (transfer == null) {
      _logger.w('Transfer $transferId not found for completion');
      _activeTransferId = null;
      return null;
    }

    if (_tempDir == null) {
      _logger.e('Cannot save file: temp dir not initialized');
      _incomingTransfers.remove(transferId);
      _activeTransferId = null;
      return null;
    }
    
    final filePath = '${_tempDir!.path}/${transfer.fileName}';

    // CRIT-008 fix: Close file handle instead of combining chunks in memory
    if (transfer.fileHandle != null) {
      try {
        await transfer.fileHandle!.close();
        _logger.i('File handle closed for ${transfer.fileName}');
      } catch (e) {
        _logger.e('Failed to close file handle: $e');
        _incomingTransfers.remove(transferId);
        _activeTransferId = null;
        return null;
      }
    } else {
      // Fallback: combine chunks from memory (legacy base64 path)
      _logger.i('Completing transfer for ${transfer.fileName}, ${transfer.chunks.length} chunks received');
      final allBytes = BytesBuilder();
      for (final chunk in transfer.chunks) {
        allBytes.add(chunk);
      }
      final file = File(filePath);
      await file.writeAsBytes(allBytes.toBytes());
    }

    // Verify file was written
    final file = File(filePath);
    if (await file.exists()) {
      final savedSize = await file.length();
      _logger.i('File received and saved: $filePath (${formatBytes(savedSize)}, expected ${formatBytes(transfer.fileSize)})');
    } else {
      _logger.e('ERROR: File was not written to disk!');
    }

    // Clean up transfer state
    _incomingTransfers.remove(transferId);
    _activeTransferId = null;

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
  /// CRIT-008 fix: File handle for streaming writes to disk instead of buffering in memory.
  RandomAccessFile? _fileHandle;
  final List<Uint8List> chunks;
  final DateTime startedAt;

  _IncomingTransfer({
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    RandomAccessFile? fileHandle,
    List<Uint8List>? chunks,
    DateTime? startedAt,
  })  : _fileHandle = fileHandle,
        chunks = chunks ?? [],
        startedAt = startedAt ?? DateTime.now();

  RandomAccessFile? get fileHandle => _fileHandle;
  set fileHandle(RandomAccessFile? value) => _fileHandle = value;
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
