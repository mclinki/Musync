import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/protocol_message.dart';
import 'package:musync_mimo/core/models/device_info.dart';
import 'package:musync_mimo/core/models/audio_session.dart';

void main() {
  group('ProtocolMessage', () {
    test('encodes and decodes correctly', () {
      final msg = ProtocolMessage(
        type: MessageType.heartbeat,
        payload: {'key': 'value'},
        timestampMs: 1234567890,
      );

      final encoded = msg.encode();
      final decoded = ProtocolMessage.decode(encoded);

      expect(decoded.type, MessageType.heartbeat);
      expect(decoded.payload['key'], 'value');
      expect(decoded.timestampMs, 1234567890);
    });

    test('join message contains device info', () {
      final device = DeviceInfo(
        id: 'test-id',
        name: 'Test Device',
        type: DeviceType.phone,
        ip: '192.168.1.100',
        port: 7890,
        discoveredAt: DateTime.now(),
      );

      final msg = ProtocolMessage.join(
        device: device,
      );

      expect(msg.type, MessageType.join);
      expect(msg.payload['device']['name'], 'Test Device');
      expect(msg.payload['device']['id'], 'test-id');
    });

    test('play message contains timing info', () {
      final msg = ProtocolMessage.play(
        startAtMs: 1000000,
        trackSource: '/path/to/file.mp3',
        sourceType: AudioSourceType.localFile,
        seekPositionMs: 5000,
      );

      expect(msg.type, MessageType.play);
      expect(msg.payload['start_at_ms'], 1000000);
      expect(msg.payload['track_source'], '/path/to/file.mp3');
      expect(msg.payload['source_type'], 'localFile');
      expect(msg.payload['seek_position_ms'], 5000);
    });

    test('sync response contains timestamps', () {
      final msg = ProtocolMessage.syncResponse(
        t1: 1000,
        t2: 1005,
        t3: 1010,
      );

      expect(msg.type, MessageType.syncResponse);
      expect(msg.payload['t1'], 1000);
      expect(msg.payload['t2'], 1005);
      expect(msg.payload['t3'], 1010);
    });

    test('pause message contains position', () {
      final msg = ProtocolMessage.pause(positionMs: 30000);

      expect(msg.type, MessageType.pause);
      expect(msg.payload['position_ms'], 30000);
    });

    test('unknown type decodes to error', () {
      final decoded = ProtocolMessage.decode('{"type":"unknown_type","payload":{},"ts":0}');
      expect(decoded.type, MessageType.error);
    });

    test('volumeControl message contains volume', () {
      final msg = ProtocolMessage.volumeControl(volume: 0.75);

      expect(msg.type, MessageType.volumeControl);
      expect(msg.payload['volume'], 0.75);

      final encoded = msg.encode();
      final decoded = ProtocolMessage.decode(encoded);
      expect(decoded.type, MessageType.volumeControl);
      expect(decoded.payload['volume'], 0.75);
    });
  });

  group('DeviceInfo', () {
    test('serializes to and from JSON', () {
      final device = DeviceInfo(
        id: 'abc-123',
        name: 'My Phone',
        type: DeviceType.phone,
        ip: '192.168.1.50',
        port: 7890,
        appVersion: '1.0.0',
        role: DeviceRole.host,
        discoveredAt: DateTime.now(),
      );

      final json = device.toJson();
      final restored = DeviceInfo.fromJson(json);

      expect(restored.id, device.id);
      expect(restored.name, device.name);
      expect(restored.type, DeviceType.phone);
      expect(restored.ip, device.ip);
      expect(restored.port, device.port);
    });

    test('creates from mDNS records', () {
      final device = DeviceInfo.fromMdns(
        name: 'musync-session',
        ip: '192.168.1.100',
        port: 7890,
        txtRecords: {
          'device_id': 'mdns-123',
          'device_type': 'tablet',
          'app_version': '0.1.0',
          'role': 'host',
        },
      );

      expect(device.id, 'mdns-123');
      expect(device.type, DeviceType.tablet);
      expect(device.role, DeviceRole.host);
    });

    test('copyWith works correctly', () {
      final original = DeviceInfo(
        id: 'id-1',
        name: 'Original',
        type: DeviceType.phone,
        ip: '192.168.1.1',
        port: 7890,
        discoveredAt: DateTime.now(),
      );

      final modified = original.copyWith(name: 'Modified', ip: '192.168.1.2');

      expect(modified.id, 'id-1');
      expect(modified.name, 'Modified');
      expect(modified.ip, '192.168.1.2');
      expect(modified.port, 7890);
    });
  });
}
