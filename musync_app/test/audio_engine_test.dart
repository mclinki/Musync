import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/audio_session.dart';

void main() {
  group('AudioTrack', () {
    test('creates from file path', () {
      final track = AudioTrack.fromFilePath('/music/My Song.mp3');
      expect(track.title, 'My Song');
      expect(track.source, '/music/My Song.mp3');
      expect(track.sourceType, AudioSourceType.localFile);
    });

    test('creates from URL', () {
      final track = AudioTrack.fromUrl('https://radio.example.com/stream');
      expect(track.source, 'https://radio.example.com/stream');
      expect(track.sourceType, AudioSourceType.url);
    });

    test('serializes to and from JSON', () {
      final track = AudioTrack(
        id: 'track-1',
        title: 'Test Song',
        artist: 'Test Artist',
        album: 'Test Album',
        source: '/path/to/song.mp3',
        sourceType: AudioSourceType.localFile,
        durationMs: 180000,
      );

      final json = track.toJson();
      final restored = AudioTrack.fromJson(json);

      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.sourceType, track.sourceType);
    });
  });
}
