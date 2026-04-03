import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/core.dart';
import 'package:musync_mimo/core/network/websocket_client.dart';

void main() {
  group('WebSocketClient - Session PIN', () {
    test('accepts sessionPin parameter', () {
      final client = WebSocketClient(
        hostIp: '192.168.1.1',
        hostPort: 7890,
        sessionPin: '123456',
      );

      expect(client.sessionPin, '123456');
    });

    test('sessionPin is null by default', () {
      final client = WebSocketClient(
        hostIp: '192.168.1.1',
        hostPort: 7890,
      );

      expect(client.sessionPin, isNull);
    });
  });

  group('AppConstants - Certificate pinning', () {
    test('expectedCertFingerprint is defined', () {
      // Should be a string (empty by default, set to fingerprint for pinning)
      expect(AppConstants.expectedCertFingerprint, isA<String>());
    });

    test('expectedCertFingerprint is empty by default (legacy mode)', () {
      expect(AppConstants.expectedCertFingerprint, isEmpty);
    });
  });

  group('ClientEvent - Rejection handling', () {
    test('rejected event contains reason message', () {
      final event = ClientEvent(
        type: ClientEventType.rejected,
        message: 'Invalid session PIN',
      );

      expect(event.message, 'Invalid session PIN');
    });
  });
}
