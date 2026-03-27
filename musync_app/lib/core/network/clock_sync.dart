import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:logger/logger.dart';

/// A single NTP-like clock synchronization sample.
class ClockSample {
  final int t1; // Time request sent (client)
  final int t2; // Time request received (server)
  final int t3; // Time response sent (server)
  final int t4; // Time response received (client)

  const ClockSample(this.t1, this.t2, this.t3, this.t4);

  /// Round-trip delay.
  int get delay => (t4 - t1) - (t3 - t2);

  /// Clock offset from server.
  double get offset => ((t2 - t1) + (t3 - t4)) / 2.0;

  @override
  String toString() => 'ClockSample(offset: ${offset.toStringAsFixed(2)}ms, delay: ${delay}ms)';
}

/// Statistics about clock synchronization quality.
class ClockSyncStats {
  final double offsetMs;
  final double driftPpm;
  final double jitterMs;
  final int sampleCount;
  final DateTime lastCalibration;
  final bool isCalibrated;

  const ClockSyncStats({
    required this.offsetMs,
    required this.driftPpm,
    required this.jitterMs,
    required this.sampleCount,
    required this.lastCalibration,
    required this.isCalibrated,
  });

  String get qualityLabel {
    if (!isCalibrated) return 'Non calibré';
    if (jitterMs < 5) return 'Excellent';
    if (jitterMs < 15) return 'Bon';
    if (jitterMs < 30) return 'Acceptable';
    return 'Dégradé';
  }
}

/// NTP-like clock synchronization engine.
///
/// Synchronizes the local clock with a remote reference clock
/// using a simplified NTP protocol over WebSocket.
///
/// The engine:
/// 1. Exchanges timestamp pairs with the reference
/// 2. Filters outliers using statistical methods
/// 3. Computes clock offset and drift rate
/// 4. Provides a [syncedTimeMs] getter for synchronized time
class ClockSyncEngine {
  final Logger _logger;
  final int _samplesPerCalibration;

  // State
  double _offsetMs = 0;
  double _driftPpm = 0;
  double _jitterMs = 0;
  int _sampleCount = 0;
  DateTime? _lastCalibration;
  DateTime? _previousCalibration;
  double _previousOffset = 0;

  // Sample history for drift calculation
  final Queue<ClockSample> _samples = Queue();
  final Queue<double> _offsetHistory = Queue();

  // Callback for sending sync requests
  final Future<ClockSample> Function()? onSyncRequest;

  // Calibration timer
  Timer? _calibrationTimer;

  ClockSyncEngine({
    this.onSyncRequest,
    Logger? logger,
    int samplesPerCalibration = 8,
  })  : _logger = logger ?? Logger(),
        _samplesPerCalibration = samplesPerCalibration;

  // ── Public API ──

  /// Current synchronized time in milliseconds since epoch.
  int get syncedTimeMs {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Apply offset + drift correction
    final elapsedSinceCalibration =
        _lastCalibration != null ? now - _lastCalibration!.millisecondsSinceEpoch : 0;
    final driftCorrection = _driftPpm * elapsedSinceCalibration / 1000.0;
    return (now + _offsetMs + driftCorrection).round();
  }

  /// Current synchronization statistics.
  ClockSyncStats get stats => ClockSyncStats(
        offsetMs: _offsetMs,
        driftPpm: _driftPpm,
        jitterMs: _jitterMs,
        sampleCount: _sampleCount,
        lastCalibration: _lastCalibration ?? DateTime.fromMillisecondsSinceEpoch(0),
        isCalibrated: _lastCalibration != null,
      );

  /// Whether the clock has been calibrated at least once.
  bool get isCalibrated => _lastCalibration != null;

  /// Perform a full calibration cycle.
  /// Returns true if calibration succeeded.
  Future<bool> calibrate() async {
    if (onSyncRequest == null) {
      _logger.w('Cannot calibrate: no sync request callback');
      return false;
    }

    _logger.i('Starting clock calibration...');

    final samples = <ClockSample>[];

    for (int i = 0; i < _samplesPerCalibration; i++) {
      try {
        final sample = await onSyncRequest!();
        samples.add(sample);
        _logger.d('Sample $i: $sample');

        // Small delay between samples to avoid flooding
        if (i < _samplesPerCalibration - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        _logger.w('Sync request failed at sample $i: $e');
      }
    }

    if (samples.length < 3) {
      _logger.e('Not enough samples for calibration (${samples.length}/$_samplesPerCalibration)');
      return false;
    }

    _processCalibrationSamples(samples);
    return true;
  }

  /// Start automatic periodic calibration.
  void startAutoCalibration({Duration interval = const Duration(seconds: 30)}) {
    stopAutoCalibration();
    _calibrationTimer = Timer.periodic(interval, (_) async {
      await calibrate();
    });
    _logger.i('Auto-calibration started (interval: ${interval.inSeconds}s)');
  }

  /// Stop automatic calibration.
  void stopAutoCalibration() {
    _calibrationTimer?.cancel();
    _calibrationTimer = null;
  }

  /// Process a single sync response from the host.
  /// Called by the WebSocket client when it receives a sync_response.
  void processSyncResponse(ClockSample sample) {
    _samples.add(sample);
    _offsetHistory.add(sample.offset);

    // Keep history bounded
    while (_samples.length > 50) {
      _samples.removeFirst();
    }
    while (_offsetHistory.length > 50) {
      _offsetHistory.removeFirst();
    }
  }

  /// Add a sample directly (for host-side processing).
  void addSample(ClockSample sample) {
    _samples.add(sample);
    _offsetHistory.add(sample.offset);
  }

  /// Dispose resources.
  void dispose() {
    stopAutoCalibration();
    _samples.clear();
    _offsetHistory.clear();
  }

  // ── Internal processing ──

  void _processCalibrationSamples(List<ClockSample> samples) {
    // Step 1: Filter outliers using IQR method
    final filtered = _filterOutliers(samples);

    if (filtered.isEmpty) {
      _logger.w('All samples were outliers');
      return;
    }

    // Step 2: Calculate new offset (median of filtered samples)
    final offsets = filtered.map((s) => s.offset).toList()..sort();
    final newOffset = _median(offsets);

    // Step 3: Calculate jitter (standard deviation of offsets)
    final mean = offsets.reduce((a, b) => a + b) / offsets.length;
    final variance = offsets.map((o) => (o - mean) * (o - mean)).reduce((a, b) => a + b) / offsets.length;
    final newJitter = sqrt(variance);

    // Step 4: Calculate drift if we have previous calibration
    final now = DateTime.now();
    if (_lastCalibration != null && _previousCalibration != null) {
      final elapsedSec = (now.millisecondsSinceEpoch - _previousCalibration!.millisecondsSinceEpoch) / 1000.0;
      if (elapsedSec > 0) {
        final offsetChange = newOffset - _previousOffset;
        // Drift in ppm (parts per million)
        _driftPpm = (offsetChange / elapsedSec) * 1000.0;
      }
    }

    // Step 5: Update state
    _previousCalibration = _lastCalibration;
    _previousOffset = _offsetMs;
    _offsetMs = newOffset;
    _jitterMs = newJitter;
    _sampleCount = filtered.length;
    _lastCalibration = now;

    _logger.i(
      'Calibration complete: offset=${_offsetMs.toStringAsFixed(2)}ms, '
      'drift=${_driftPpm.toStringAsFixed(4)}ppm, '
      'jitter=${_jitterMs.toStringAsFixed(2)}ms, '
      'samples=${filtered.length}/${samples.length}',
    );
  }

  /// Filter outliers using the Interquartile Range (IQR) method.
  List<ClockSample> _filterOutliers(List<ClockSample> samples) {
    if (samples.length <= 3) return samples;

    final offsets = samples.map((s) => s.offset).toList()..sort();
    final q1 = _percentile(offsets, 25);
    final q3 = _percentile(offsets, 75);
    final iqr = q3 - q1;
    final lowerBound = q1 - 1.5 * iqr;
    final upperBound = q3 + 1.5 * iqr;

    return samples.where((s) {
      return s.offset >= lowerBound && s.offset <= upperBound;
    }).toList();
  }

  double _percentile(List<double> sorted, double p) {
    final index = (p / 100.0) * (sorted.length - 1);
    final lower = index.floor();
    final upper = index.ceil();
    if (lower == upper) return sorted[lower];
    final fraction = index - lower;
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
  }

  double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}
