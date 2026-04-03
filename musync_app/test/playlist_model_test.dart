import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/playlist.dart';
import 'package:musync_mimo/core/models/audio_session.dart';

void main() {
  AudioTrack _track(String path) => AudioTrack.fromFilePath(path);

  group('Playlist shuffle', () {
    test('returns null for empty playlist', () {
      const playlist = Playlist();
      expect(playlist.shuffle(), isNull);
    });

    test('returns null for single track', () {
      final playlist = Playlist(tracks: [_track('/a.mp3')]);
      expect(playlist.shuffle(), isNull);
    });

    test('sets isShuffled to true', () {
      final playlist = Playlist(
        tracks: [
          _track('/a.mp3'),
          _track('/b.mp3'),
          _track('/c.mp3'),
        ],
        currentIndex: 0,
      );
      final shuffled = playlist.shuffle();
      expect(shuffled, isNotNull);
      expect(shuffled!.isShuffled, isTrue);
    });

    test('keeps current track at position 0', () {
      final playlist = Playlist(
        tracks: [
          _track('/a.mp3'),
          _track('/b.mp3'),
          _track('/c.mp3'),
        ],
        currentIndex: 1,
      );
      final shuffled = playlist.shuffle();
      expect(shuffled, isNotNull);
      expect(shuffled!.tracks[0].source, '/b.mp3');
      expect(shuffled.currentIndex, 0);
    });

    test('preserves all tracks after shuffle', () {
      final playlist = Playlist(
        tracks: [
          _track('/a.mp3'),
          _track('/b.mp3'),
          _track('/c.mp3'),
          _track('/d.mp3'),
        ],
        currentIndex: 0,
      );
      final shuffled = playlist.shuffle();
      expect(shuffled, isNotNull);
      expect(shuffled!.length, 4);
      final sources = shuffled.tracks.map((t) => t.source).toSet();
      expect(sources.contains('/a.mp3'), isTrue);
      expect(sources.contains('/b.mp3'), isTrue);
      expect(sources.contains('/c.mp3'), isTrue);
      expect(sources.contains('/d.mp3'), isTrue);
    });

    test('preserves repeatMode after shuffle', () {
      final playlist = Playlist(
        tracks: [_track('/a.mp3'), _track('/b.mp3')],
        repeatMode: RepeatMode.one,
      );
      final shuffled = playlist.shuffle();
      expect(shuffled, isNotNull);
      expect(shuffled!.repeatMode, RepeatMode.one);
    });
  });

  group('Playlist toggleRepeat', () {
    test('cycles off -> all -> one -> off', () {
      var playlist = const Playlist(repeatMode: RepeatMode.off);
      playlist = playlist.toggleRepeat();
      expect(playlist.repeatMode, RepeatMode.all);

      playlist = playlist.toggleRepeat();
      expect(playlist.repeatMode, RepeatMode.one);

      playlist = playlist.toggleRepeat();
      expect(playlist.repeatMode, RepeatMode.off);
    });

    test('preserves other state when toggling repeat', () {
      final playlist = Playlist(
        tracks: [_track('/a.mp3'), _track('/b.mp3')],
        currentIndex: 1,
        repeatMode: RepeatMode.off,
        isShuffled: true,
      );
      final toggled = playlist.toggleRepeat();
      expect(toggled.repeatMode, RepeatMode.all);
      expect(toggled.currentIndex, 1);
      expect(toggled.isShuffled, isTrue);
      expect(toggled.length, 2);
    });
  });

  group('Playlist toJson / fromJson', () {
    test('serializes and deserializes with all fields', () {
      final playlist = Playlist(
        tracks: [
          _track('/a.mp3'),
          _track('/b.mp3'),
        ],
        currentIndex: 1,
        repeatMode: RepeatMode.one,
        isShuffled: true,
      );

      final json = playlist.toJson();
      expect(json['currentIndex'], 1);
      expect(json['repeatMode'], 'one');
      expect(json['isShuffled'], isTrue);
      expect(json['tracks'], isA<List>());
      expect((json['tracks'] as List).length, 2);

      final restored = Playlist.fromJson(json);
      expect(restored.currentIndex, 1);
      expect(restored.repeatMode, RepeatMode.one);
      expect(restored.isShuffled, isTrue);
      expect(restored.length, 2);
      expect(restored.tracks[0].source, '/a.mp3');
      expect(restored.tracks[1].source, '/b.mp3');
    });

    test('deserializes with missing fields uses defaults', () {
      final json = <String, dynamic>{
        'tracks': [
          {'id': '1', 'title': 'Test', 'source': '/test.mp3', 'source_type': 'localFile'},
        ],
      };

      final playlist = Playlist.fromJson(json);
      expect(playlist.currentIndex, 0);
      expect(playlist.repeatMode, RepeatMode.off);
      expect(playlist.isShuffled, isFalse);
      expect(playlist.length, 1);
    });

    test('deserializes each repeatMode variant', () {
      for (final mode in RepeatMode.values) {
        final json = <String, dynamic>{
          'tracks': [],
          'repeatMode': mode.name,
        };
        final playlist = Playlist.fromJson(json);
        expect(playlist.repeatMode, mode);
      }
    });

    test('clamps currentIndex on fromJson if out of range', () {
      final json = <String, dynamic>{
        'tracks': [
          {'id': '1', 'title': 'Test', 'source': '/test.mp3', 'source_type': 'localFile'},
        ],
        'currentIndex': 99,
      };
      final playlist = Playlist.fromJson(json);
      expect(playlist.currentIndex, 0);
    });

    test('handles empty tracks list', () {
      const playlist = Playlist();
      final json = playlist.toJson();
      final restored = Playlist.fromJson(json);
      expect(restored.isEmpty, isTrue);
      expect(restored.repeatMode, RepeatMode.off);
    });
  });

  group('Playlist copyWith', () {
    test('updates only specified fields', () {
      final playlist = Playlist(
        tracks: [_track('/a.mp3')],
        currentIndex: 0,
        repeatMode: RepeatMode.off,
        isShuffled: false,
      );
      final updated = playlist.copyWith(repeatMode: RepeatMode.all, isShuffled: true);
      expect(updated.repeatMode, RepeatMode.all);
      expect(updated.isShuffled, isTrue);
      expect(updated.currentIndex, 0);
      expect(updated.length, 1);
    });
  });
}
