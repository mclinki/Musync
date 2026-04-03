import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Information about an available update.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;
  final int fileSizeBytes;
  final String fileName;
  final DateTime publishedAt;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.fileName,
    required this.publishedAt,
  });

  bool get isNewer => _compareVersions(latestVersion, currentVersion) > 0;

  /// Compare two semantic version strings (e.g., "0.1.20" vs "0.1.19").
  /// Returns > 0 if a > b, < 0 if a < b, 0 if equal.
  static int _compareVersions(String a, String b) {
    final partsA = a.split('.').map(int.parse).toList();
    final partsB = b.split('.').map(int.parse).toList();
    final maxLen = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < maxLen; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

  /// Human-readable file size.
  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Progress of an APK download.
class DownloadProgress {
  final int receivedBytes;
  final int totalBytes;
  double get progress => totalBytes > 0 ? receivedBytes / totalBytes : 0;

  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });
}

/// Service for checking and downloading app updates from GitHub Releases.
class UpdateService {
  final Logger _logger;
  final String owner;
  final String repo;

  UpdateService({
    Logger? logger,
    this.owner = 'mclinki',
    this.repo = 'Musync',
  }) : _logger = logger ?? Logger();

  /// Check GitHub Releases for a newer version.
  /// Returns [UpdateInfo] if a newer version is available, null otherwise.
  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      _logger.i('Checking for updates (current: $currentVersion)...');

      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
      );
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'MusyncMIMO/$currentVersion');

      final response = await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _logger.w('GitHub API returned ${response.statusCode}');
        return null;
      }

      final body = await response.transform(utf8.decoder).join();

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?)?.replaceAll('v', '') ?? '';
      final releaseNotes = (json['body'] as String?) ?? '';
      final publishedAt = DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now();

      if (tagName.isEmpty) {
        _logger.w('No tag_name in release');
        return null;
      }

      // Find APK asset
      final assets = (json['assets'] as List?) ?? [];
      String? downloadUrl;
      int fileSize = 0;
      String fileName = '';

      for (final asset in assets) {
        final assetName = (asset['name'] as String?) ?? '';
        if (assetName.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          fileSize = (asset['size'] as num?)?.toInt() ?? 0;
          fileName = assetName;
          break;
        }
      }

      if (downloadUrl == null) {
        _logger.w('No APK asset found in release $tagName');
        return null;
      }

      final info = UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        fileSizeBytes: fileSize,
        fileName: fileName,
        publishedAt: publishedAt,
      );

      _logger.i('Latest version: $tagName (current: $currentVersion, newer: ${info.isNewer})');
      return info;
    } catch (e) {
      _logger.e('Failed to check for updates: $e');
      return null;
    } finally {
      // MED-009 fix: Always close the HTTP client
      client.close();
    }
  }

  /// Download an APK update. Returns the local file path if successful.
  /// [onProgress] is called with download progress updates.
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    _logger.i('Downloading update: ${updateInfo.fileName} (${updateInfo.fileSizeFormatted})');

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/${updateInfo.fileName}';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.parse(updateInfo.downloadUrl));
      request.headers.set('User-Agent', 'MusyncMIMO/${updateInfo.currentVersion}');

      final response = await request.close().timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        _logger.e('Download failed with status ${response.statusCode}');
        return null;
      }

      final file = File(filePath);
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(
          receivedBytes: received,
          totalBytes: updateInfo.fileSizeBytes,
        ));
      }

      await sink.flush();
      await sink.close();

      _logger.i('Download complete: $filePath ($received bytes)');
      return filePath;
    } catch (e) {
      _logger.e('Failed to download update: $e');
      return null;
    } finally {
      // MED-009 fix: Always close the HTTP client
      client.close();
    }
  }

  /// Get the path to a previously downloaded update (if any).
  Future<String?> getDownloadedUpdatePath(String fileName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      _logger.d('Failed to get downloaded update path: $e');
    }
    return null;
  }
}
