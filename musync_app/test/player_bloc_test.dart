import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musync_mimo/core/core.dart';
import 'package:musync_mimo/features/player/bloc/player_bloc.dart';

// ── Mocks ──

class MockSessionManager extends Mock implements SessionManager {}

class MockAudioEngine extends Mock implements AudioEngine {}

class MockStream<T> extends Mock implements Stream<T> {}

// ── Fakes ──

class FakeAudioTrack extends Fake implements AudioTrack {}

void main() {
  late MockSessionManager sessionManager;
  late MockAudioEngine audioEngine;

  setUpAll(() {
    registerFallbackValue(FakeAudioTrack());
  });

  setUp(() {
    sessionManager = MockSessionManager();
    audioEngine = MockAudioEngine();

    // Stub audioEngine on sessionManager
    when(() => sessionManager.audioEngine).thenReturn(audioEngine);
    when(() => sessionManager.role).thenReturn(DeviceRole.none);

    // Stub audio engine streams
    when(() => audioEngine.stateStream).thenAnswer(
      (_) => Stream<AudioEngineState>.fromIterable([]),
    );
    when(() => audioEngine.positionStream).thenAnswer(
      (_) => Stream<Duration>.fromIterable([]),
    );
    when(() => audioEngine.position).thenReturn(Duration.zero);
    when(() => audioEngine.duration).thenReturn(const Duration(minutes: 3));
  });

  group('PlayerBloc', () {
    test('initial state is correct', () {
      final bloc = PlayerBloc(sessionManager: sessionManager);
      expect(bloc.state.status, PlayerStatus.idle);
      expect(bloc.state.currentTrack, isNull);
      expect(bloc.state.playlist.isEmpty, true);
      expect(bloc.state.position, Duration.zero);
      expect(bloc.state.volume, 1.0);
      bloc.close();
    });

    blocTest<PlayerBloc, PlayerState>(
      'LoadTrackRequested loads track and creates playlist',
      build: () {
        when(() => audioEngine.loadTrack(any())).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(LoadTrackRequested(
        AudioTrack.fromFilePath('/test/song.mp3'),
      )),
      wait: const Duration(milliseconds: 600),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.loading),
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.paused)
            .having((s) => s.playlist.length, 'playlist length', 1)
            .having((s) => s.currentTrack, 'currentTrack', isNotNull),
      ],
      verify: (_) {
        verify(() => audioEngine.loadTrack(any())).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'AddToQueueRequested adds track to playlist',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(AddToQueueRequested(AudioTrack.fromFilePath('/test/song1.mp3')));
        bloc.add(AddToQueueRequested(AudioTrack.fromFilePath('/test/song2.mp3')));
      },
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 1),
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 2),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'RemoveFromQueueRequested removes track',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(AddToQueueRequested(AudioTrack.fromFilePath('/test/song1.mp3')));
        bloc.add(AddToQueueRequested(AudioTrack.fromFilePath('/test/song2.mp3')));
        bloc.add(const RemoveFromQueueRequested(0));
      },
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 1),
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 2),
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 1),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'ClearQueueRequested clears playlist and resets track',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(AddToQueueRequested(AudioTrack.fromFilePath('/test/song1.mp3')));
        bloc.add(const ClearQueueRequested());
      },
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.playlist.length, 'playlist length', 1),
        isA<PlayerState>()
            .having((s) => s.playlist.isEmpty, 'playlist empty', true)
            .having((s) => s.currentTrack, 'currentTrack', isNull)
            .having((s) => s.status, 'status', PlayerStatus.idle),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'PlayRequested plays when track is loaded (solo mode)',
      build: () {
        when(() => audioEngine.play()).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      seed: () => PlayerState(
        status: PlayerStatus.paused,
        currentTrack: AudioTrack.fromFilePath('/test/song.mp3'),
        playlist: Playlist(
          tracks: [AudioTrack.fromFilePath('/test/song.mp3')],
        ),
      ),
      act: (bloc) => bloc.add(const PlayRequested()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.playing),
      ],
      verify: (_) {
        verify(() => audioEngine.play()).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'PlayRequested emits error when no track selected',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const PlayRequested()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'PauseRequested pauses playback (solo mode)',
      build: () {
        when(() => audioEngine.pause()).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song.mp3'),
      ),
      act: (bloc) => bloc.add(const PauseRequested()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.paused),
      ],
      verify: (_) {
        verify(() => audioEngine.pause()).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'StopRequested stops playback and resets position',
      build: () {
        when(() => audioEngine.stop()).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song.mp3'),
        position: const Duration(seconds: 30),
      ),
      act: (bloc) => bloc.add(const StopRequested()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.idle)
            .having((s) => s.position, 'position', Duration.zero),
      ],
      verify: (_) {
        verify(() => audioEngine.stop()).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'VolumeChanged updates volume',
      build: () {
        when(() => audioEngine.setVolume(any())).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const VolumeChanged(0.5)),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.volume, 'volume', 0.5),
      ],
      verify: (_) {
        verify(() => audioEngine.setVolume(0.5)).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'SeekRequested seeks to position',
      build: () {
        when(() => audioEngine.seek(any())).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const SeekRequested(Duration(seconds: 60))),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.position, 'position', const Duration(seconds: 60)),
      ],
      verify: (_) {
        verify(() => audioEngine.seek(const Duration(seconds: 60))).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'SkipNextRequested advances to next track',
      build: () {
        when(() => audioEngine.loadTrack(any())).thenAnswer((_) async {});
        when(() => audioEngine.play()).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song1.mp3'),
        playlist: Playlist(
          tracks: [
            AudioTrack.fromFilePath('/test/song1.mp3'),
            AudioTrack.fromFilePath('/test/song2.mp3'),
          ],
          currentIndex: 0,
        ),
      ),
      act: (bloc) => bloc.add(const SkipNextRequested()),
      wait: const Duration(milliseconds: 400),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.loading)
            .having((s) => s.playlist.currentIndex, 'currentIndex', 1),
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.playing),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'SkipNextRequested does nothing at end of queue',
      build: () => PlayerBloc(sessionManager: sessionManager),
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song2.mp3'),
        playlist: Playlist(
          tracks: [
            AudioTrack.fromFilePath('/test/song1.mp3'),
            AudioTrack.fromFilePath('/test/song2.mp3'),
          ],
          currentIndex: 1,
        ),
      ),
      act: (bloc) => bloc.add(const SkipNextRequested()),
      expect: () => [], // No state change
    );

    blocTest<PlayerBloc, PlayerState>(
      'SkipPreviousRequested restarts track if > 3s in',
      build: () {
        when(() => audioEngine.seek(any())).thenAnswer((_) async {});
        return PlayerBloc(sessionManager: sessionManager);
      },
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song1.mp3'),
        position: const Duration(seconds: 10),
        playlist: Playlist(
          tracks: [AudioTrack.fromFilePath('/test/song1.mp3')],
          currentIndex: 0,
        ),
      ),
      act: (bloc) => bloc.add(const SkipPreviousRequested()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.position, 'position', Duration.zero),
      ],
      verify: (_) {
        verify(() => audioEngine.seek(Duration.zero)).called(1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'PositionUpdated updates position',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const PositionUpdated(Duration(seconds: 45))),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.position, 'position', const Duration(seconds: 45)),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'AudioStateChanged playing updates status',
      build: () => PlayerBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const AudioStateChanged(AudioEngineState.playing)),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.playing),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'AudioStateChanged idle while playing triggers TrackCompleted',
      build: () => PlayerBloc(sessionManager: sessionManager),
      seed: () => PlayerState(
        status: PlayerStatus.playing,
        currentTrack: AudioTrack.fromFilePath('/test/song1.mp3'),
        playlist: Playlist(
          tracks: [AudioTrack.fromFilePath('/test/song1.mp3')],
          currentIndex: 0,
        ),
      ),
      act: (bloc) => bloc.add(const AudioStateChanged(AudioEngineState.idle)),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.idle),
      ],
    );
  });

  group('Playlist model', () {
    test('addTrack increases length', () {
      const playlist = Playlist();
      final updated = playlist.addTrack(AudioTrack.fromFilePath('/test.mp3'));
      expect(updated.length, 1);
      expect(updated.currentTrack, isNotNull);
    });

    test('hasNext/hasPrevious work correctly', () {
      final playlist = Playlist(
        tracks: [
          AudioTrack.fromFilePath('/a.mp3'),
          AudioTrack.fromFilePath('/b.mp3'),
          AudioTrack.fromFilePath('/c.mp3'),
        ],
        currentIndex: 1,
      );
      expect(playlist.hasNext, true);
      expect(playlist.hasPrevious, true);

      final atStart = playlist.goTo(0);
      expect(atStart.hasNext, true);
      expect(atStart.hasPrevious, false);

      final atEnd = playlist.goTo(2);
      expect(atEnd.hasNext, false);
      expect(atEnd.hasPrevious, true);
    });

    test('skipNext returns new playlist or null', () {
      final playlist = Playlist(
        tracks: [
          AudioTrack.fromFilePath('/a.mp3'),
          AudioTrack.fromFilePath('/b.mp3'),
        ],
        currentIndex: 0,
      );
      final next = playlist.skipNext();
      expect(next, isNotNull);
      expect(next!.currentIndex, 1);

      final noMore = next.skipNext();
      expect(noMore, isNull);
    });

    test('removeTrack adjusts currentIndex', () {
      final playlist = Playlist(
        tracks: [
          AudioTrack.fromFilePath('/a.mp3'),
          AudioTrack.fromFilePath('/b.mp3'),
          AudioTrack.fromFilePath('/c.mp3'),
        ],
        currentIndex: 2,
      );
      final updated = playlist.removeTrack(2);
      expect(updated.length, 2);
      expect(updated.currentIndex, 1); // Clamped
    });

    test('clear returns empty playlist', () {
      final playlist = Playlist(
        tracks: [AudioTrack.fromFilePath('/a.mp3')],
      );
      final cleared = playlist.clear();
      expect(cleared.isEmpty, true);
      expect(cleared.currentIndex, 0);
    });
  });
}
