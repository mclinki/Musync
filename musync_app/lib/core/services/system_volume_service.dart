import 'dart:async';
import 'package:logger/logger.dart';
import 'package:volume_controller/volume_controller.dart';

/// Service that controls the system volume across platforms.
///
/// Uses `volume_controller` package which supports:
/// - Android: AudioManager.STREAM_MUSIC
/// - Windows: CoreAudio API (via platform channel)
/// - iOS: MPVolumeView (requires user interaction)
/// - macOS: NSSound
///
/// The audio engine (just_audio) volume is kept at 1.0 (max) so that
/// the system volume slider is the only volume control the user interacts with.
class SystemVolumeService {
  final Logger _logger;
  final VolumeController _controller = VolumeController.instance;
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();

  StreamSubscription<double>? _volumeSub;
  double _currentVolume = 1.0;
  bool _isInitialized = false;

  SystemVolumeService({Logger? logger}) : _logger = logger ?? Logger();

  /// Current system volume (0.0 to 1.0).
  double get currentVolume => _currentVolume;

  /// Stream of system volume changes.
  Stream<double> get volumeStream => _volumeController.stream;

  /// Initialize the service and start listening to volume changes.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get initial volume
      _currentVolume = await _controller.getVolume();
      _logger.i('System volume initialized: ${_currentVolume.toStringAsFixed(2)}');

      // Listen to system volume changes (hardware buttons, etc.)
      _volumeSub = _controller.addListener(
        (volume) {
          if (volume != _currentVolume) {
            _currentVolume = volume;
            if (!_volumeController.isClosed) {
              _volumeController.add(volume);
            }
            _logger.d('System volume changed (external): ${volume.toStringAsFixed(2)}');
          }
        },
        fetchInitialVolume: false, // Already fetched above
      );

      // Don't show system UI overlay when changing volume
      _controller.showSystemUI = false;

      _isInitialized = true;
    } catch (e) {
      _logger.w('SystemVolumeService init failed (fallback to internal volume): $e');
      // Fallback: service still works but won't reflect hardware button changes
      _isInitialized = true;
    }
  }

  /// Set the system volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (clamped == _currentVolume) return;

    try {
      await _controller.setVolume(clamped);
      _currentVolume = clamped;
      if (!_volumeController.isClosed) {
        _volumeController.add(clamped);
      }
      _logger.d('System volume set to: ${clamped.toStringAsFixed(2)}');
    } catch (e) {
      _logger.e('Failed to set system volume: $e');
      rethrow;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _volumeSub?.cancel();
    _volumeSub = null;
    if (!_volumeController.isClosed) {
      await _volumeController.close();
    }
    _isInitialized = false;
    _logger.i('SystemVolumeService disposed');
  }
}
