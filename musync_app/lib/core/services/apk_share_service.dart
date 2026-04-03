import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';

/// Serves the APK file over HTTP on the local network.
///
/// This allows devices WITHOUT Musync to download and install the app
/// by opening a URL in their browser.
///
/// Flow:
/// 1. [start] — copies APK to a temp location, starts HTTP server
/// 2. [shareUrl] — the URL to share (e.g., http://192.168.1.5:8080/apk)
/// 3. Target device opens URL in browser → downloads APK → installs
/// 4. [stop] — stops server, cleans up temp file
class ApkShareService {
  static const int _defaultPort = 8080;
  static const String _channelName = AppConstants.foregroundServiceChannel;

  final Logger _logger;
  HttpServer? _server;
  String? _apkTempPath;
  int _port = _defaultPort;

  ApkShareService({Logger? logger}) : _logger = logger ?? Logger();

  /// Whether the HTTP server is running.
  bool get isRunning => _server != null;

  /// The port the server is listening on.
  int get port => _port;

  /// The URL to share with other devices.
  /// Returns null if server is not running.
  String? shareUrl(String localIp) {
    if (_server == null) return null;
    return 'http://$localIp:$_port/apk';
  }

  /// Start the HTTP server and serve the APK.
  ///
  /// Returns the server port on success, or null on failure.
  /// Use [shareUrl] with the local IP to get the full URL.
  Future<int?> start({int port = _defaultPort}) async {
    if (_server != null) {
      _logger.w('APK share server already running on port $_port');
      return _port;
    }

    try {
      // 1. Get the APK path
      final apkPath = await _getApkPath();
      if (apkPath == null) {
        _logger.e('Cannot start APK share: APK path not found');
        return null;
      }

      // 2. Copy APK to a readable temp location
      //    (on Android, the install dir may not be readable by the HTTP server)
      _apkTempPath = await _copyApkToTemp(apkPath);
      if (_apkTempPath == null) {
        _logger.e('Cannot start APK share: failed to copy APK to temp');
        return null;
      }

      // 3. Start HTTP server
      _port = port;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _logger.i('APK share server started on port $_port');

      // 4. Listen for requests
      _server!.listen((HttpRequest request) async {
        await _handleRequest(request);
      });

      return _port;
    } catch (e) {
      _logger.e('Failed to start APK share server: $e');
      await stop();
      return null;
    }
  }

  /// Stop the HTTP server and clean up.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;

    // Clean up temp APK file
    if (_apkTempPath != null) {
      try {
        final tempFile = File(_apkTempPath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
          _logger.d('Cleaned up temp APK: $_apkTempPath');
        }
      } catch (e) {
        _logger.w('Failed to clean up temp APK: $e');
      }
      _apkTempPath = null;
    }

    _logger.i('APK share server stopped');
  }

  /// Handle an incoming HTTP request.
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    _logger.d('APK share request: ${request.method} $path from ${request.connectionInfo?.remoteAddress}');

    if (path == '/apk' || path == '/apk/') {
      await _serveApk(request);
    } else if (path == '/' || path == '') {
      await _serveLandingPage(request);
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found. Use /apk to download.')
        ..close();
    }
  }

  /// Serve the APK file for download.
  Future<void> _serveApk(HttpRequest request) async {
    if (_apkTempPath == null) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('APK not available')
        ..close();
      return;
    }

    final apkFile = File(_apkTempPath!);
    if (!await apkFile.exists()) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('APK file not found')
        ..close();
      return;
    }

    final fileSize = await apkFile.length();
    final fileName = 'musync-${AppConstants.appVersion}.apk';

    request.response
      ..headers.contentType = ContentType('application', 'vnd.android.package-archive')
      ..headers.set('Content-Disposition', 'attachment; filename="$fileName"')
      ..headers.set('Content-Length', fileSize.toString());

    _logger.i('Serving APK: $fileName (${_formatBytes(fileSize)})');

    await request.response.addStream(apkFile.openRead());
    await request.response.close();
  }

  /// Serve a simple landing page with download link.
  Future<void> _serveLandingPage(HttpRequest request) async {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MusyncMIMO - Download</title>
  <style>
    body { font-family: sans-serif; text-align: center; padding: 40px; }
    h1 { color: #1a73e8; }
    a.btn { 
      display: inline-block; padding: 15px 30px; margin: 20px;
      background: #1a73e8; color: white; text-decoration: none;
      border-radius: 8px; font-size: 18px;
    }
    p { color: #666; margin: 10px; }
  </style>
</head>
<body>
  <h1>MusyncMIMO</h1>
  <p>Synchronisez la musique sur plusieurs appareils</p>
  <a class="btn" href="/apk">Télécharger l'APK (v${AppConstants.appVersion})</a>
  <p><small>Ouvrez ce lien sur l'appareil Android cible</small></p>
</body>
</html>
''';

    request.response
      ..headers.contentType = ContentType.html
      ..write(html)
      ..close();
  }

  /// Get the APK file path using platform channel.
  Future<String?> _getApkPath() async {
    if (!Platform.isAndroid) {
      _logger.w('APK sharing only supported on Android');
      return null;
    }

    try {
      const channel = MethodChannel(_channelName);
      final path = await channel.invokeMethod<String>('getApkPath');
      if (path != null) {
        _logger.i('APK path: $path');
      }
      return path;
    } catch (e) {
      _logger.e('Failed to get APK path via platform channel: $e');
      return null;
    }
  }

  /// Copy APK to a temp location readable by the HTTP server.
  Future<String?> _copyApkToTemp(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        _logger.e('Source APK not found: $sourcePath');
        return null;
      }

      // Use system temp directory
      final tempDir = Directory.systemTemp;
      final tempPath = '${tempDir.path}/musync-${AppConstants.appVersion}.apk';

      await sourceFile.copy(tempPath);
      _logger.i('APK copied to temp: $tempPath (${_formatBytes(await File(tempPath).length())})');
      return tempPath;
    } catch (e) {
      _logger.e('Failed to copy APK to temp: $e');
      return null;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
