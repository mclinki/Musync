import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:logger/logger.dart';
import '../app_constants.dart';

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

  // Kalman filter state
  double _kalmanOffset = 0;     // Estimated offset (ms)
  double _kalmanDrift = 0;      // Estimated drift (ms/s)
  double _kalmanP00 = 100.0;    // Covariance: offset uncertainty
  double _kalmanP01 = 0.0;      // Covariance: offset-drift cross
  double _kalmanP10 = 0.0;      // Covariance: drift-offset cross
  double _kalmanP11 = 10.0;     // Covariance: drift uncertainty
  bool _kalmanInitialized = false;

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
    int samplesPerCalibration = AppConstants.samplesPerCalibration,
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

        // Reduced delay between samples for faster calibration
        if (i < _samplesPerCalibration - 1) {
          await Future.delayed(const Duration(milliseconds: AppConstants.calibrationSampleDelayMs));
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

  /// Calibrate directly from pre-collected samples.
  /// Used when sync exchanges are managed externally (e.g., by WebSocketClient).
  void calibrateFromSamples(List<ClockSample> samples) {
    if (samples.length < 3) {
      _logger.w('Not enough samples for calibration (${samples.length})');
      return;
    }
    _processCalibrationSamples(samples);
  }

  /// Start automatic periodic calibration.
  /// Uses adaptive intervals based on sync quality:
  /// - Stable (jitter < 5ms):  15s interval (save battery/bandwidth)
  /// - Normal (jitter 5-15ms): 10s interval
  /// - Unstable (jitter > 15ms): 3s interval (recover quickly)
  /// - Critical (jitter > 30ms): 1s interval (degraded mode)
  void startAutoCalibration({Duration interval = const Duration(milliseconds: AppConstants.autoCalibrationIntervalMs)}) {
    stopAutoCalibration();
    _baseCalibrationInterval = interval;
    _scheduleAdaptiveCalibration();
    _logger.i('Adaptive auto-calibration started');
  }

  Duration _baseCalibrationInterval = Duration(milliseconds: AppConstants.autoCalibrationIntervalMs);

  void _scheduleAdaptiveCalibration() {
    _calibrationTimer?.cancel();

    final nextInterval = _computeAdaptiveInterval();

    _calibrationTimer = Timer(nextInterval, () async {
      // MED-003 fix: Check timer is still active BEFORE and AFTER async calibrate()
      if (_calibrationTimer == null) return;
      await calibrate();
      if (_calibrationTimer != null) {
        _scheduleAdaptiveCalibration();
      }
    });

    _logger.d('Next calibration in ${nextInterval.inMilliseconds}ms (jitter: ${_jitterMs.toStringAsFixed(1)}ms)');
  }

  Duration _computeAdaptiveInterval() {
    if (!isCalibrated) return const Duration(seconds: 3); // First calibration: fast

    if (_jitterMs < 5) {
      return const Duration(seconds: 15); // Stable: relax
    } else if (_jitterMs < 15) {
      return _baseCalibrationInterval; // Normal: use base (10s)
    } else if (_jitterMs < 30) {
      return const Duration(seconds: 3); // Unstable: fast recovery
    } else {
      return const Duration(seconds: 1); // Critical: aggressive
    }
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
    while (_samples.length > AppConstants.maxSampleHistory) {
      _samples.removeFirst();
    }
    while (_offsetHistory.length > AppConstants.maxSampleHistory) {
      _offsetHistory.removeFirst();
    }
  }

  /// Add a sample directly (for host-side processing).
  void addSample(ClockSample sample) {
    processSyncResponse(sample);
  }

  /// Check if recalibration is urgently needed based on predicted drift.
  /// Returns true if estimated drift since last calibration exceeds [thresholdMs].
  bool needsRecalibration({double thresholdMs = 5.0}) {
    if (!isCalibrated) return true;
    final elapsedSec = (DateTime.now().millisecondsSinceEpoch - _lastCalibration!.millisecondsSinceEpoch) / 1000.0;
    final predictedDrift = _driftPpm * elapsedSec / 1000.0; // ppm * seconds / 1000 = ms
    return predictedDrift.abs() > thresholdMs;
  }

  /// Force immediate recalibration (e.g., when playback drift detected).
  /// Returns true if calibration succeeded.
  Future<bool> forceRecalibrate() async {
    _logger.w('Force recalibration requested');
    // Reset Kalman confidence to be more responsive
    _kalmanP00 = 100.0;
    _kalmanP11 = 10.0;
    return await calibrate();
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

    // Step 2: Calculate raw offset (median of filtered samples)
    final offsets = filtered.map((s) => s.offset).toList()..sort();
    final rawOffset = _median(offsets);

    // Step 3: Calculate jitter (standard deviation of offsets)
    final mean = offsets.reduce((a, b) => a + b) / offsets.length;
    final variance = offsets.map((o) => (o - mean) * (o - mean)).reduce((a, b) => a + b) / offsets.length;
    final rawJitter = sqrt(variance);

    // Step 4: Apply Kalman filter for smoother, more accurate estimation
    final now = DateTime.now();
    final elapsedSec = _lastCalibration != null
        ? (now.millisecondsSinceEpoch - _lastCalibration!.millisecondsSinceEpoch) / 1000.0
        : 1.0;

    _kalmanFilterUpdate(rawOffset, rawJitter, elapsedSec);

    // Step 5: Calculate drift from Kalman estimate
    _driftPpm = _kalmanDrift * 1000.0; // Convert ms/s to ppm

    // Step 6: Update state with Kalman-filtered values
    _previousCalibration = _lastCalibration;
    _previousOffset = _offsetMs;
    _offsetMs = _kalmanOffset;
    _jitterMs = rawJitter;
    _sampleCount = filtered.length;
    _lastCalibration = now;

    _logger.i(
      'Calibration complete: offset=${_offsetMs.toStringAsFixed(2)}ms '
      '(raw=${rawOffset.toStringAsFixed(2)}ms), '
      'drift=${_driftPpm.toStringAsFixed(4)}ppm, '
      'jitter=${_jitterMs.toStringAsFixed(2)}ms, '
      'samples=${filtered.length}/${samples.length}',
    );
  }

  /// Kalman filter update for clock offset and drift estimation.
  ///
  /// State vector: [offset_ms, drift_ms_per_sec]
  /// The filter models clock behavior as:
  ///   offset(t+dt) = offset(t) + drift * dt + process_noise
  ///
  /// This provides smoother estimates than raw median, especially
  /// when network jitter is high.
  void _kalmanFilterUpdate(double measuredOffset, double measurementNoise, double dt) {
    // Measurement noise (R): based on observed jitter, min 1ms
    final R = max(measurementNoise * measurementNoise, 1.0);

    if (!_kalmanInitialized) {
      // First measurement: initialize state
      _kalmanOffset = measuredOffset;
      _kalmanDrift = 0;
      _kalmanP00 = R;
      _kalmanP01 = 0;
      _kalmanP10 = 0;
      _kalmanP11 = 10.0;
      _kalmanInitialized = true;
      return;
    }

    // ── Predict step ──
    // State prediction: offset += drift * dt
    _kalmanOffset += _kalmanDrift * dt;

    // Process noise: how much we expect the real system to deviate from model
    // Higher = more responsive but noisier
    final Q00 = 0.5 * dt * dt;  // Offset process noise
    final Q01 = 0.5 * dt;       // Cross noise
    final Q10 = 0.5 * dt;
    final Q11 = 1.0 * dt;       // Drift process noise (ppm can change)

    // Covariance prediction: P = F * P * F^T + Q
    // F = [[1, dt], [0, 1]]
    final p00 = _kalmanP00 + dt * (_kalmanP10 + _kalmanP01) + dt * dt * _kalmanP11 + Q00;
    final p01 = _kalmanP01 + dt * _kalmanP11 + Q01;
    final p10 = _kalmanP10 + dt * _kalmanP11 + Q10;
    final p11 = _kalmanP11 + Q11;

    // ── Update step ──
    // Measurement model: we directly observe offset (H = [1, 0])
    // Innovation: y = measurement - predicted
    final innovation = measuredOffset - _kalmanOffset;

    // Kalman gain: K = P * H^T * (H * P * H^T + R)^(-1)
    final S = p00 + R;  // Innovation covariance
    final K0 = p00 / S; // Gain for offset
    final K1 = p10 / S; // Gain for drift

    // State update
    _kalmanOffset += K0 * innovation;
    _kalmanDrift += K1 * innovation;

    // Covariance update: P = (I - K * H) * P
    _kalmanP00 = (1 - K0) * p00;
    _kalmanP01 = (1 - K0) * p01;
    _kalmanP10 = -K1 * p00 + p10;
    _kalmanP11 = -K1 * p01 + p11;
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
