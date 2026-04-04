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

    // ── AGENT-12: Comprehensive schema migration tests ──

    group('Schema migration', () {
      test('v1 with full data migrates to v2 preserving all fields', () {
        final v1Json = {
          'version': 1,
          'session_id': 'session-abc',
          'state': 'playing',
          'current_track': {
            'title': 'My Song',
            'artist': 'Artist',
            'source': '/music/song.mp3',
            'sourceType': 'localFile',
          },
          'position_ms': 42000,
          'volume': 0.75,
          'devices': [
            {
              'id': 'dev-1',
              'name': 'Phone',
              'type': 'phone',
              'ip': '192.168.1.10',
              'port': 7890,
              'discoveredAt': '2026-04-01T00:00:00.000Z',
            },
          ],
          'playlist': [
            {
              'title': 'Song 1',
              'source': '/music/song1.mp3',
              'sourceType': 'localFile',
            },
            {
              'title': 'Song 2',
              'source': '/music/song2.mp3',
              'sourceType': 'localFile',
            },
          ],
          'current_index': 1,
          'created_at': '2026-04-01T10:00:00.000Z',
          'updated_at': '2026-04-01T10:05:00.000Z',
        };

        final ctx = SessionContext.fromJson(v1Json);

        // Version upgraded
        expect(ctx.version, equals(currentContextVersion));
        // All v1 fields preserved
        expect(ctx.sessionId, equals('session-abc'));
        expect(ctx.state, equals(SessionState.playing));
        expect(ctx.currentTrack?.title, equals('My Song'));
        expect(ctx.positionMs, equals(42000));
        expect(ctx.volume, equals(0.75));
        expect(ctx.devices.length, equals(1));
        expect(ctx.devices[0].name, equals('Phone'));
        expect(ctx.playlist.length, equals(2));
        expect(ctx.currentIndex, equals(1));
        // v2 fields added with defaults
        expect(ctx.volumes, isEmpty);
        expect(ctx.clockOffsets, isEmpty);
      });

      test('v2 roundtrip preserves data (no migration needed)', () {
        final v2Json = {
          'version': 2,
          'session_id': 'session-v2',
          'state': 'paused',
          'position_ms': 30000,
          'volume': 0.5,
          'devices': [],
          'playlist': [],
          'current_index': 0,
          'volumes': {'dev-1': 0.8, 'dev-2': 0.6},
          'clock_offsets': {'dev-1': 2.5, 'dev-2': -1.3},
          'created_at': '2026-04-02T00:00:00.000Z',
          'updated_at': '2026-04-02T00:01:00.000Z',
        };

        final ctx = SessionContext.fromJson(v2Json);

        expect(ctx.version, equals(currentContextVersion));
        expect(ctx.sessionId, equals('session-v2'));
        expect(ctx.state, equals(SessionState.paused));
        expect(ctx.positionMs, equals(30000));
        expect(ctx.volume, equals(0.5));
        expect(ctx.volumes, equals({'dev-1': 0.8, 'dev-2': 0.6}));
        expect(ctx.clockOffsets, equals({'dev-1': 2.5, 'dev-2': -1.3}));

        // Roundtrip: toJson → fromJson should be identical
        final roundtrip = SessionContext.fromJson(ctx.toJson());
        expect(roundtrip.sessionId, equals(ctx.sessionId));
        expect(roundtrip.state, equals(ctx.state));
        expect(roundtrip.volumes, equals(ctx.volumes));
        expect(roundtrip.clockOffsets, equals(ctx.clockOffsets));
      });

      test('v1 with missing optional fields migrates safely', () {
        final minimalV1 = {
          'version': 1,
          'session_id': 'minimal',
          'state': 'waiting',
          'created_at': '2026-04-01T00:00:00.000Z',
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        final ctx = SessionContext.fromJson(minimalV1);

        expect(ctx.sessionId, equals('minimal'));
        expect(ctx.state, equals(SessionState.waiting));
        expect(ctx.positionMs, equals(0));
        expect(ctx.volume, equals(1.0));
        expect(ctx.devices, isEmpty);
        expect(ctx.playlist, isEmpty);
        expect(ctx.volumes, isEmpty);
        expect(ctx.clockOffsets, isEmpty);
      });

      test('v1 with unknown state migrates to waiting (safe default)', () {
        final v1Json = {
          'version': 1,
          'session_id': 'unknown-state',
          'state': 'future_state_that_does_not_exist',
          'created_at': '2026-04-01T00:00:00.000Z',
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        final ctx = SessionContext.fromJson(v1Json);

        expect(ctx.state, equals(SessionState.waiting)); // Safe fallback
        expect(ctx.sessionId, equals('unknown-state'));
      });

      test('v1 with numeric types as strings migrates correctly', () {
        final v1Json = {
          'version': 1,
          'session_id': 'numeric-test',
          'state': 'playing',
          'position_ms': 12345,
          'volume': 0.9,
          'current_index': 2,
          'created_at': '2026-04-01T00:00:00.000Z',
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        final ctx = SessionContext.fromJson(v1Json);

        expect(ctx.positionMs, equals(12345));
        expect(ctx.volume, equals(0.9));
        expect(ctx.currentIndex, equals(2));
      });

      test('migration does not mutate original JSON', () {
        final v1Json = {
          'version': 1,
          'session_id': 'immutable-test',
          'state': 'waiting',
          'created_at': '2026-04-01T00:00:00.000Z',
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        // Parse once
        SessionContext.fromJson(v1Json);

        // Original JSON should NOT have been mutated
        expect(v1Json.containsKey('volumes'), isFalse);
        expect(v1Json.containsKey('clock_offsets'), isFalse);
      });

      test('future version (v3+) is handled gracefully', () {
        final futureJson = {
          'version': 99,
          'session_id': 'future-session',
          'state': 'playing',
          'position_ms': 0,
          'volume': 1.0,
          'devices': [],
          'playlist': [],
          'current_index': 0,
          'volumes': {},
          'clock_offsets': {},
          'created_at': '2026-04-01T00:00:00.000Z',
          'updated_at': '2026-04-01T00:00:00.000Z',
        };

        // Should not crash — migration is a no-op for future versions
        final ctx = SessionContext.fromJson(futureJson);
        expect(ctx.sessionId, equals('future-session'));
        expect(ctx.version, equals(currentContextVersion));
      });
    });
  });
}
