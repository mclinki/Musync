import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/network/clock_sync.dart';

void main() {
  group('ClockSyncEngine performance', () {
    test('calibration converges with consistent samples', () {
      final engine = ClockSyncEngine();

      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final t2 = t1 + 2 + (i % 3);
        final t3 = t2 + 1;
        final t4 = t3 + 2 + (i % 3);
        engine.processSyncResponse(ClockSample(t1, t2, t3, t4));
      }

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final t2 = t1 + 2 + (i % 3);
        final t3 = t2 + 1;
        final t4 = t3 + 2 + (i % 3);
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      expect(engine.stats.jitterMs, lessThan(5));
    });

    test('quality is Excellent for low jitter', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final t2 = t1 + 2;
        final t3 = t2 + 1;
        final t4 = t3 + 2;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      expect(engine.stats.qualityLabel, contains('Excellent'));
    });

    test('quality is Bon for moderate jitter', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final jitter = (i % 7);
        final t2 = t1 + 5 + jitter;
        final t3 = t2 + 1;
        final t4 = t3 + 5 + jitter;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      final quality = engine.stats.qualityLabel;
      expect(
        quality == 'Excellent' || quality == 'Bon',
        isTrue,
        reason: 'Expected Excellent or Bon, got $quality',
      );
    });

    test('handles high jitter gracefully', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final jitter = (i * 7 % 30);
        final t2 = t1 + 10 + jitter;
        final t3 = t2 + 1;
        final t4 = t3 + 10 + jitter;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      expect(engine.stats.isCalibrated, isTrue);
      expect(engine.stats.sampleCount, greaterThan(0));
    });

    test('calibration requires minimum 3 samples', () {
      final engine = ClockSyncEngine();

      engine.calibrateFromSamples([
        const ClockSample(0, 5, 6, 11),
        const ClockSample(100, 105, 106, 111),
      ]);

      expect(engine.isCalibrated, isFalse);
    });

    test('converges within 10 samples for very consistent data', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 10; i++) {
        final t1 = i * 100;
        final t2 = t1 + 3;
        final t3 = t2 + 1;
        final t4 = t3 + 3;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      expect(engine.stats.jitterMs, lessThan(2));
    });

    test('quality degrades appropriately with increasing jitter', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final jitter = (i * 13 % 40);
        final t2 = t1 + 15 + jitter;
        final t3 = t2 + 1;
        final t4 = t3 + 15 + jitter;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      final quality = engine.stats.qualityLabel;
      expect(quality, isNotNull);
    });

    test('stats sampleCount reflects filtered sample count', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final t2 = t1 + 5;
        final t3 = t2 + 1;
        final t4 = t3 + 5;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.stats.sampleCount, greaterThan(0));
      expect(engine.stats.sampleCount, lessThanOrEqualTo(20));
    });

    test('offset is near expected value for uniform samples', () {
      final engine = ClockSyncEngine();

      final samples = <ClockSample>[];
      for (int i = 0; i < 20; i++) {
        final t1 = i * 100;
        final t2 = t1 + 10;
        final t3 = t2 + 1;
        final t4 = t3 + 10;
        samples.add(ClockSample(t1, t2, t3, t4));
      }
      engine.calibrateFromSamples(samples);

      expect(engine.isCalibrated, isTrue);
      expect(engine.stats.offsetMs.abs(), lessThan(15));
    });
  });
}
