import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/session_context.dart';
import 'package:musync_mimo/core/models/audio_session.dart';
import 'package:musync_mimo/core/models/device_info.dart';

void main() {
  group('SessionContext', () {
    test('empty creates valid context', () {
      final ctx = SessionContext.empty(sessionId: 'test-123');
      expect(ctx.sessionId, equals('test-123'));
      expect(ctx.state, equals(SessionState.waiting));
      expect(ctx.version, equals(currentContextVersion));
      expect(ctx.devices, isEmpty);
      expect(ctx.playlist, isEmpty);
    });

    test('toJson roundtrip preserves data', () {
      final ctx = SessionContext(
        sessionId: 's1',
        state: SessionState.playing,
        currentTrack: AudioTrack.fromFilePath('/music/song.mp3'),
        positionMs: 5000,
        volume: 0.8,
        createdAt: DateTime(2026, 4, 2),
        updatedAt: DateTime(2026, 4, 2),
      );

      final json = ctx.toJson();
      final restored = SessionContext.fromJson(json);

      expect(restored.sessionId, equals('s1'));
      expect(restored.state, equals(SessionState.playing));
      expect(restored.positionMs, equals(5000));
      expect(restored.volume, equals(0.8));
      expect(restored.currentTrack?.title, equals('song'));
      expect(restored.version, equals(currentContextVersion));
    });

    test('copyWith updates fields and updatedAt', () {
      final ctx = SessionContext.empty(sessionId: 's1');
      final updated = ctx.copyWith(
        state: SessionState.playing,
        positionMs: 1000,
      );

      expect(updated.state, equals(SessionState.playing));
      expect(updated.positionMs, equals(1000));
      expect(updated.sessionId, equals('s1'));
      expect(updated.updatedAt.isAfter(ctx.updatedAt) ||
          updated.updatedAt.isAtSameMomentAs(ctx.updatedAt),
          isTrue);
    });

    test('copyWith clearTrack removes current track', () {
      final ctx = SessionContext(
        sessionId: 's1',
        state: SessionState.playing,
        currentTrack: AudioTrack.fromFilePath('/music/song.mp3'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = ctx.copyWith(clearTrack: true);
      expect(cleared.currentTrack, isNull);
    });

    test('migration v1 to v2 adds volumes and clockOffsets', () {
      final v1Json = {
        'version': 1,
        'session_id': 'old-session',
        'state': 'waiting',
        'position_ms': 0,
        'volume': 1.0,
        'devices': [],
        'playlist': [],
        'current_index': 0,
        'created_at': '2026-04-01T00:00:00.000Z',
        'updated_at': '2026-04-01T00:00:00.000Z',
      };

      final ctx = SessionContext.fromJson(v1Json);
      expect(ctx.version, equals(currentContextVersion));
      expect(ctx.volumes, isEmpty);
      expect(ctx.clockOffsets, isEmpty);
      expect(ctx.sessionId, equals('old-session'));
    });

    test('summary contains session info', () {
      final ctx = SessionContext(
        sessionId: 'abc',
        state: SessionState.playing,
        currentTrack: AudioTrack.fromFilePath('/music/test.mp3'),
        positionMs: 15000,
        volume: 0.75,
        devices: [
          DeviceInfo(
            id: 'd1',
            name: 'Phone',
            type: DeviceType.phone,
            ip: '192.168.1.1',
            port: 7890,
            discoveredAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final summary = ctx.summary;
      expect(summary, contains('abc'));
      expect(summary, contains('test'));
      expect(summary, contains('15.0s'));
      expect(summary, contains('Appareils: 1'));
      expect(summary, contains('75%'));
    });

    test('fromJson handles null currentTrack gracefully', () {
      final json = {
        'version': 2,
        'session_id': 's1',
        'state': 'waiting',
        'current_track': null,
        'position_ms': 0,
        'volume': 1.0,
        'devices': [],
        'playlist': [],
        'current_index': 0,
        'volumes': {},
        'clock_offsets': {},
        'created_at': '2026-04-02T00:00:00.000Z',
        'updated_at': '2026-04-02T00:00:00.000Z',
      };

      final ctx = SessionContext.fromJson(json);
      expect(ctx.currentTrack, isNull);
      expect(ctx.devices, isEmpty);
    });
  });
}
