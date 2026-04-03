import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';

/// Controls the background service to keep the app alive during active sessions.
///
/// On Android, this uses a foreground service with a persistent notification.
/// On iOS, this configures an AVAudioSession with playback category to allow
/// background audio when the app is minimized or the screen is locked.
class ForegroundService {
  static const _channel = MethodChannel(AppConstants.foregroundServiceChannel);
  final Logger _logger;
  bool _isRunning = false;

  ForegroundService({Logger? logger}) : _logger = logger ?? Logger();

  bool get isRunning => _isRunning;

  /// Start the background service.
  /// Android: starts foreground service with notification.
  /// iOS: configures AVAudioSession for background playback.
  Future<void> start({String title = 'MusyncMIMO'}) async {
    if (Platform.isAndroid) {
      await _startAndroid(title);
    } else if (Platform.isIOS) {
      await _startIosBackground();
    } else {
      _logger.d('Background service not supported on this platform');
    }
  }

  Future<void> _startAndroid(String title) async {
    if (_isRunning) {
      _logger.w('Foreground service already running');
      return;
    }

    try {
      await _channel.invokeMethod('startForeground', {'title': title});
      _isRunning = true;
      _logger.i('Foreground service started');
    } catch (e) {
      _logger.e('Failed to start foreground service: $e');
    }
  }

  Future<void> _startIosBackground() async {
    if (_isRunning) {
      _logger.w('iOS background session already active');
      return;
    }

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      _isRunning = true;
      _logger.i('iOS background audio session configured');
    } catch (e) {
      _logger.w('Failed to configure iOS background audio: $e');
    }
  }

  /// Stop the background service.
  Future<void> stop() async {
    if (Platform.isAndroid) {
      await _stopAndroid();
    } else if (Platform.isIOS) {
      await _stopIosBackground();
    }
  }

  Future<void> _stopAndroid() async {
    if (!_isRunning) return;

    try {
      await _channel.invokeMethod('stopForeground');
      _isRunning = false;
      _logger.i('Foreground service stopped');
    } catch (e) {
      _logger.e('Failed to stop foreground service: $e');
    }
  }

  Future<void> _stopIosBackground() async {
    if (!_isRunning) return;

    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
      _isRunning = false;
      _logger.i('iOS background audio session deactivated');
    } catch (e) {
      _logger.w('Failed to deactivate iOS background audio: $e');
    }
  }
}
