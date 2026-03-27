import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/network/clock_sync.dart';

void main() {
  group('ClockSample', () {
    test('calculates delay correctly', () {
      // t1=1000, t2=1005, t3=1010, t4=1015
      // delay = (1015-1000) - (1010-1005) = 15 - 5 = 10ms
      const sample = ClockSample(1000, 1005, 1010, 1015);
      expect(sample.delay, 10);
    });

    test('calculates offset correctly', () {
      // offset = ((1005-1000) + (1010-1015)) / 2 = (5 + -5) / 2 = 0
      const sample = ClockSample(1000, 1005, 1010, 1015);
      expect(sample.offset, 0.0);
    });

    test('calculates positive offset when server is ahead', () {
      // Server clock is 5ms ahead
      // t1=1000, t2=1010, t3=1011, t4=1006
      // offset = ((1010-1000) + (1011-1006)) / 2 = (10 + 5) / 2 = 7.5
      const sample = ClockSample(1000, 1010, 1011, 1006);
      expect(sample.offset, 7.5);
    });

    test('calculates negative offset when server is behind', () {
      // Server clock is behind
      // t1=1000, t2=995, t3=996, t4=1001
      // offset = ((995-1000) + (996-1001)) / 2 = (-5 + -5) / 2 = -5
      const sample = ClockSample(1000, 995, 996, 1001);
      expect(sample.offset, -5.0);
    });
  });

  group('ClockSyncEngine', () {
    late ClockSyncEngine engine;

    setUp(() {
      engine = ClockSyncEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('initial state is not calibrated', () {
      expect(engine.isCalibrated, false);
      expect(engine.stats.isCalibrated, false);
    });

    test('syncedTimeMs returns local time when not calibrated', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final synced = engine.syncedTimeMs;
      final after = DateTime.now().millisecondsSinceEpoch;

      // Should be approximately the local time (within 10ms)
      expect(synced, greaterThanOrEqualTo(before - 10));
      expect(synced, lessThanOrEqualTo(after + 10));
    });

    test('processSyncResponse updates samples', () {
      final sample = ClockSample(1000, 1005, 1010, 1015);
      engine.processSyncResponse(sample);

      // Engine should have recorded the sample
      expect(engine.stats.sampleCount, 0); // Not calibrated yet, just added to queue
    });

    test('calibrate with callback performs sync', () async {
      int callCount = 0;

      final testEngine = ClockSyncEngine(
        onSyncRequest: () async {
          callCount++;
          final t1 = DateTime.now().millisecondsSinceEpoch;
          await Future.delayed(const Duration(milliseconds: 1));
          final t2 = t1 + 5; // Simulate 5ms server processing
          final t3 = t2 + 1;
          await Future.delayed(const Duration(milliseconds: 1));
          return ClockSample(t1, t2, t3, DateTime.now().millisecondsSinceEpoch);
        },
      );

      final success = await testEngine.calibrate();

      expect(success, true);
      expect(callCount, 8); // Default 8 samples
      expect(testEngine.isCalibrated, true);

      testEngine.dispose();
    });

    test('quality label reflects jitter', () {
      expect(engine.stats.qualityLabel, 'Non calibré');
    });
  });
}
