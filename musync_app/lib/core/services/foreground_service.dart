import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';

/// Controls the Android foreground service to keep the app alive in background.
///
/// On Android, this prevents the OS from killing the app during active sessions.
/// On iOS, this is a no-op (iOS handles background audio via AudioSession).
class ForegroundService {
  static const _channel = MethodChannel(AppConstants.foregroundServiceChannel);
  final Logger _logger;
  bool _isRunning = false;

  ForegroundService({Logger? logger}) : _logger = logger ?? Logger();

  bool get isRunning => _isRunning;

  /// Start the foreground service with a notification.
  Future<void> start({String title = 'MusyncMIMO'}) async {
    if (!Platform.isAndroid) {
      _logger.d('Foreground service is Android-only, skipping');
      return;
    }

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

  /// Stop the foreground service.
  Future<void> stop() async {
    if (!Platform.isAndroid) return;

    if (!_isRunning) return;

    try {
      await _channel.invokeMethod('stopForeground');
      _isRunning = false;
      _logger.i('Foreground service stopped');
    } catch (e) {
      _logger.e('Failed to stop foreground service: $e');
    }
  }
}
