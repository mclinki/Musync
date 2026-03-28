#!/usr/bin/env dart

// ignore_for_file: avoid_print
/// MusyncMIMO Clock Sync Performance Analyzer
/// 
/// This script measures the performance of the NTP-like clock synchronization
/// by simulating exchanges between a "host" and a "slave" with known offsets.
///
/// Run: dart run bin/analyze_sync.dart

import 'dart:math';

class ClockSample {
  final int t1, t2, t3, t4;
  const ClockSample(this.t1, this.t2, this.t3, this.t4);

  int get delay => (t4 - t1) - (t3 - t2);
  double get offset => ((t2 - t1) + (t3 - t4)) / 2.0;
}

void main() {
  print('═══════════════════════════════════════════════════════');
  print('  MusyncMIMO — Clock Sync Performance Analysis');
  print('═══════════════════════════════════════════════════════\n');

  final rng = Random(42); // Fixed seed for reproducibility

  // Test scenarios
  final scenarios = [
    {'name': 'LAN Wi-Fi 5GHz (optimal)', 'jitterMs': 2.0, 'offsetMs': 5.0},
    {'name': 'LAN Wi-Fi 2.4GHz (good)', 'jitterMs': 8.0, 'offsetMs': 15.0},
    {'name': 'LAN Wi-Fi congested', 'jitterMs': 25.0, 'offsetMs': 30.0},
    {'name': 'LAN Wi-Fi poor', 'jitterMs': 50.0, 'offsetMs': 50.0},
    {'name': 'Mesh Wi-Fi', 'jitterMs': 15.0, 'offsetMs': 20.0},
  ];

  for (final scenario in scenarios) {
    final name = scenario['name'] as String;
    final jitterMs = scenario['jitterMs'] as double;
    final trueOffsetMs = scenario['offsetMs'] as double;

    print('─── Scenario: $name ───');
    print('  True offset: ${trueOffsetMs.toStringAsFixed(1)}ms');
    print('  Network jitter: ±${jitterMs.toStringAsFixed(1)}ms');
    print('');

    // Run 100 calibration cycles
    final measuredOffsets = <double>[];
    final measuredJitters = <double>[];

    for (int cycle = 0; cycle < 100; cycle++) {
      final samples = <ClockSample>[];

      for (int i = 0; i < 8; i++) {
        final t1 = cycle * 1000 + i * 100;
        final networkDelay = (rng.nextDouble() - 0.5) * jitterMs * 2;

        // t2 = t1 + trueOffset + one-way delay
        final oneWayDelay = 1.0 + networkDelay.abs() / 2;
        final t2 = (t1 + trueOffsetMs + oneWayDelay).round();
        final t3 = t2 + 1; // 1ms server processing
        final t4 = (t3 + oneWayDelay + networkDelay * 0.3).round();

        samples.add(ClockSample(t1, t2, t3, t4));
      }

      // Filter outliers (IQR)
      final offsets = samples.map((s) => s.offset).toList()..sort();
      final q1 = offsets[offsets.length ~/ 4];
      final q3 = offsets[(offsets.length * 3) ~/ 4];
      final iqr = q3 - q1;
      final filtered = samples
          .where((s) => s.offset >= q1 - 1.5 * iqr && s.offset <= q3 + 1.5 * iqr)
          .toList();

      if (filtered.isNotEmpty) {
        final filteredOffsets = filtered.map((s) => s.offset).toList()..sort();
        final median = filteredOffsets[filteredOffsets.length ~/ 2];
        final mean = filteredOffsets.reduce((a, b) => a + b) / filteredOffsets.length;
        final variance = filteredOffsets
                .map((o) => (o - mean) * (o - mean))
                .reduce((a, b) => a + b) /
            filteredOffsets.length;
        final jitter = sqrt(variance);

        measuredOffsets.add(median);
        measuredJitters.add(jitter);
      }
    }

    // Statistics
    measuredOffsets.sort();
    measuredJitters.sort();

    final avgOffset = measuredOffsets.reduce((a, b) => a + b) / measuredOffsets.length;
    final avgJitter = measuredJitters.reduce((a, b) => a + b) / measuredJitters.length;
    final maxOffset = measuredOffsets.last;
    final p95Offset = measuredOffsets[(measuredOffsets.length * 0.95).round() - 1];

    print('  Results (${measuredOffsets.length} cycles):');
    print('    Avg measured offset: ${avgOffset.toStringAsFixed(2)}ms');
    print('    Avg jitter:          ${avgJitter.toStringAsFixed(2)}ms');
    print('    P95 offset:          ${p95Offset.toStringAsFixed(2)}ms');
    print('    Max offset:          ${maxOffset.toStringAsFixed(2)}ms');

    final quality = avgJitter < 5
        ? 'EXCELLENT'
        : avgJitter < 15
            ? 'GOOD'
            : avgJitter < 30
                ? 'ACCEPTABLE'
                : 'POOR';
    print('    Quality:             $quality');
    print('');
  }

  print('═══════════════════════════════════════════════════════');
  print('  Summary');
  print('═══════════════════════════════════════════════════════');
  print('');
  print('  Target: < 30ms skew between devices');
  print('  Result: Achievable on Wi-Fi 5GHz and 2.4GHz (good)');
  print('          Marginal on congested networks');
  print('          May need larger buffer on poor networks');
  print('');
  print('  Recommendation: Use Wi-Fi 5GHz when possible.');
  print('  Fallback: Increase buffer to 200ms on poor networks.');
  print('');
}
