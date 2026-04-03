import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:logger/logger.dart';

class MetadataService {
  final Logger _logger;
  MetadataService({Logger? logger}) : _logger = logger ?? Logger();

  /// Parse les métadonnées ID3 d'un fichier audio.
  /// Retourne un Map avec title, artist, album, genre, year, trackNumber, duration, hasAlbumArt.
  /// Fallback sur le nom de fichier si les métadonnées sont absentes.
  Future<Map<String, dynamic>> parseMetadata(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return {};

      final metadata = await readMetadata(file);

      return {
        'title': metadata.title?.isNotEmpty == true ? metadata.title : null,
        'artist': metadata.artist?.isNotEmpty == true ? metadata.artist : null,
        'album': metadata.album?.isNotEmpty == true ? metadata.album : null,
        'genre': null, // audio_metadata_reader doesn't expose genre directly
        'year': metadata.year,
        'trackNumber': metadata.trackNumber,
        'duration': null, // audio_metadata_reader doesn't provide duration
        'hasAlbumArt': metadata.pictures.isNotEmpty,
      };
    } catch (e) {
      _logger.w('Failed to parse metadata for $filePath: $e');
      return {};
    }
  }

  /// Extraire la pochette d'album comme Uint8List (JPEG/PNG).
  Future<List<int>?> extractAlbumArt(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final metadata = await readMetadata(file);
      return metadata.pictures.isNotEmpty ? metadata.pictures.first.bytes : null;
    } catch (e) {
      _logger.w('Failed to extract album art for $filePath: $e');
      return null;
    }
  }
}
