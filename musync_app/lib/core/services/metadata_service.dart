import 'dart:io';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:logger/logger.dart';

class MetadataService {
  final Logger _logger;
  MetadataService({Logger? logger}) : _logger = logger ?? Logger();

  Future<Map<String, dynamic>> parseMetadata(String filePath) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS && !Platform.isLinux) {
      _logger.d('ID3 parsing skipped on ${Platform.operatingSystem}');
      return {};
    }
    try {
      final file = File(filePath);
      final metadata = await MetadataRetriever.fromFile(file);

      return {
        'title': metadata.trackName?.isNotEmpty == true ? metadata.trackName : null,
        'artist': metadata.trackArtistNames?.isNotEmpty == true ? metadata.trackArtistNames!.join(', ') : null,
        'album': metadata.albumName?.isNotEmpty == true ? metadata.albumName : null,
        'genre': metadata.genre?.isNotEmpty == true ? metadata.genre : null,
        'year': metadata.year,
        'trackNumber': metadata.trackNumber,
        'duration': metadata.trackDuration,
        'hasAlbumArt': metadata.albumArt != null,
      };
    } catch (e) {
      _logger.w('Failed to parse metadata for $filePath: $e');
      return {};
    }
  }

  Future<List<int>?> extractAlbumArt(String filePath) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS && !Platform.isLinux) {
      return null;
    }
    try {
      final file = File(filePath);
      final metadata = await MetadataRetriever.fromFile(file);
      return metadata.albumArt;
    } catch (e) {
      _logger.w('Failed to extract album art for $filePath: $e');
      return null;
    }
  }
}
