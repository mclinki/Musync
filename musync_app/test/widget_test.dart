// MusyncMIMO widget test

import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/models.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic smoke test - verifies core models can be instantiated
    final track = AudioTrack.fromFilePath('/test/song.mp3');
    expect(track.title, 'song');
    expect(track.sourceType, AudioSourceType.localFile);
  });

  test('AudioTrack from URL', () {
    final track = AudioTrack.fromUrl('https://example.com/song.mp3', title: 'Test Song');
    expect(track.title, 'Test Song');
    expect(track.sourceType, AudioSourceType.url);
  });

  test('AudioTrack JSON serialization', () {
    final track = AudioTrack(
      id: '123',
      title: 'Test',
      source: '/path/to/file.mp3',
      sourceType: AudioSourceType.localFile,
    );
    final json = track.toJson();
    final restored = AudioTrack.fromJson(json);
    expect(restored.id, track.id);
    expect(restored.title, track.title);
  });
}
