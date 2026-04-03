import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/core.dart';
import 'package:musync_mimo/core/services/file_transfer_service.dart';

// ── Fakes ──

class FakeProtocolMessage extends Fake implements ProtocolMessage {}

void main() {
  group('FileTransferService - Binary chunk parsing', () {
    test('parseBinaryChunkFrame parses valid frame', () {
      // Build a valid frame: [4 bytes chunkIndex][4 bytes dataLength][data...]
      final frame = BytesBuilder();
      // Chunk index = 5
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(5);
      // Data length = 3
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(3);
      // Data
      frame.add([1, 2, 3]);

      final result = FileTransferService.parseBinaryChunkFrame(frame.toBytes());

      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, [1, 2, 3]);
    });

    test('parseBinaryChunkFrame returns null for too short frame', () {
      final result = FileTransferService.parseBinaryChunkFrame([1, 2, 3]);
      expect(result, isNull);
    });

    test('parseBinaryChunkFrame returns null for incomplete data', () {
      final frame = BytesBuilder();
      // Chunk index = 0
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      // Data length = 10 (but only 2 bytes provided)
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(10);
      frame.add([1, 2]);

      final result = FileTransferService.parseBinaryChunkFrame(frame.toBytes());
      expect(result, isNull);
    });

    test('parseBinaryChunkFrame handles zero-length data', () {
      final frame = BytesBuilder();
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);
      frame.addByte(0);

      final result = FileTransferService.parseBinaryChunkFrame(frame.toBytes());
      expect(result, isNotNull);
      expect(result!.$1, 0);
      expect(result.$2, isEmpty);
    });
  });

  group('FileTransferService - Protocol message factories', () {
    test('fileTransferStart includes transferId', () {
      final msg = ProtocolMessage.fileTransferStart(
        fileName: 'test.mp3',
        fileSizeBytes: 1000,
        totalChunks: 1,
        chunkSizeBytes: 1000,
        transferId: 'abc123',
      );
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.type, MessageType.fileTransferStart);
      expect(decoded.payload['file_name'], 'test.mp3');
      expect(decoded.payload['file_size_bytes'], 1000);
      expect(decoded.payload['total_chunks'], 1);
      expect(decoded.payload['transfer_id'], 'abc123');
    });

    test('fileTransferChunk encodes base64 data', () {
      final msg = ProtocolMessage.fileTransferChunk(
        chunkIndex: 0,
        data: 'dGVzdA==', // "test" in base64
      );
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.type, MessageType.fileTransferChunk);
      expect(decoded.payload['chunk_index'], 0);
      expect(decoded.payload['data'], 'dGVzdA==');
    });

    test('fileTransferEnd has no payload', () {
      final msg = ProtocolMessage.fileTransferEnd();
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.type, MessageType.fileTransferEnd);
    });

    test('fileTransferAck has no payload', () {
      final msg = ProtocolMessage.fileTransferAck();
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.type, MessageType.fileTransferAck);
    });
  });

  group('FileTransferService - Size validation constants', () {
    test('maxFileSizeBytes is 100MB', () {
      expect(AppConstants.maxFileSizeBytes, 100 * 1024 * 1024);
    });

    test('maxMessageSizeBytes is 1MB', () {
      expect(AppConstants.maxMessageSizeBytes, 1024 * 1024);
    });

    test('fileChunkSizeBytes is 64KB', () {
      expect(AppConstants.fileChunkSizeBytes, 64 * 1024);
    });
  });

  group('TransferProgress', () {
    test('calculates percentage correctly', () {
      final progress = TransferProgress(
        fileName: 'test.mp3',
        bytesTransferred: 500,
        totalBytes: 1000,
        isIncoming: true,
      );

      expect(progress.percentage, 0.5);
    });

    test('percentage is 0 when totalBytes is 0', () {
      final progress = TransferProgress(
        fileName: 'test.mp3',
        bytesTransferred: 0,
        totalBytes: 0,
        isIncoming: true,
      );

      expect(progress.percentage, 0);
    });

    test('percentage caps at 1.0', () {
      final progress = TransferProgress(
        fileName: 'test.mp3',
        bytesTransferred: 1500,
        totalBytes: 1000,
        isIncoming: true,
      );

      expect(progress.percentage, 1.5);
    });

    test('isIncoming flag is preserved', () {
      final incoming = TransferProgress(
        fileName: 'test.mp3',
        bytesTransferred: 100,
        totalBytes: 1000,
        isIncoming: true,
      );
      final outgoing = TransferProgress(
        fileName: 'test.mp3',
        bytesTransferred: 100,
        totalBytes: 1000,
        isIncoming: false,
      );

      expect(incoming.isIncoming, isTrue);
      expect(outgoing.isIncoming, isFalse);
    });
  });
}
