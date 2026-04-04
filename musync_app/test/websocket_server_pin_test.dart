import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/core.dart';

void main() {
  group('WebSocketServer - Session PIN', () {
    test('PIN is empty by default (optional auth)', () {
      final server = WebSocketServer(
        port: 7890,
        sessionId: 'test-session',
      );

      expect(server.sessionPin, isEmpty);
    });

    test('accepts custom PIN', () {
      final server = WebSocketServer(
        port: 7890,
        sessionId: 'test-session',
        sessionPin: '123456',
      );

      expect(server.sessionPin, '123456');
    });

    test('generates valid 6-digit PINs when explicitly set', () {
      for (int i = 0; i < 10; i++) {
        final server = WebSocketServer(
          port: 7890 + i,
          sessionId: 'session$i',
          sessionPin: WebSocketServer.generatePin(),
        );

        expect(server.sessionPin.length, 6);
        final pinNum = int.tryParse(server.sessionPin);
        expect(pinNum, isNotNull);
        expect(pinNum! >= 100000 && pinNum <= 999999, isTrue);
      }
    });
  });

  group('ProtocolMessage - Session PIN', () {
    test('join message includes sessionPin when provided', () {
      final device = DeviceInfo(
        id: 'device1',
        name: 'Test Device',
        type: DeviceType.phone,
        ip: '192.168.1.2',
        port: 7890,
        discoveredAt: DateTime.now(),
      );

      final msg = ProtocolMessage.join(device: device, sessionPin: '654321');
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.payload['session_pin'], '654321');
    });

    test('join message omits sessionPin when not provided', () {
      final device = DeviceInfo(
        id: 'device1',
        name: 'Test Device',
        type: DeviceType.phone,
        ip: '192.168.1.2',
        port: 7890,
        discoveredAt: DateTime.now(),
      );

      final msg = ProtocolMessage.join(device: device);
      final decoded = ProtocolMessage.decode(msg.encode());

      expect(decoded.payload.containsKey('session_pin'), isFalse);
    });
  });

  group('AppConstants - Session PIN config', () {
    test('sessionPinLength is 6', () {
      expect(AppConstants.sessionPinLength, 6);
    });
  });
}
