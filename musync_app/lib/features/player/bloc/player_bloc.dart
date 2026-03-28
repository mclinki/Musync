import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../core/core.dart';

// ── Events ──

abstract class PlayerEvent extends Equatable {
  const PlayerEvent();

  @override
  List<Object?> get props => [];
}

class LoadTrackRequested extends PlayerEvent {
  final AudioTrack track;

  const LoadTrackRequested(this.track);

  @override
  List<Object?> get props => [track];
}

class AddToQueueRequested extends PlayerEvent {
  final AudioTrack track;

  const AddToQueueRequested(this.track);

  @override
  List<Object?> get props => [track];
}

class RemoveFromQueueRequested extends PlayerEvent {
  final int index;

  const RemoveFromQueueRequested(this.index);

  @override
  List<Object?> get props => [index];
}

class ClearQueueRequested extends PlayerEvent {
  const ClearQueueRequested();
}

class PlayRequested extends PlayerEvent {
  const PlayRequested();
}

class PauseRequested extends PlayerEvent {
  const PauseRequested();
}

class ResumeRequested extends PlayerEvent {
  const ResumeRequested();
}

class StopRequested extends PlayerEvent {
  const StopRequested();
}

class SkipNextRequested extends PlayerEvent {
  const SkipNextRequested();
}

class SkipPreviousRequested extends PlayerEvent {
  const SkipPreviousRequested();
}

class SeekRequested extends PlayerEvent {
  final Duration position;

  const SeekRequested(this.position);

  @override
  List<Object?> get props => [position];
}

class VolumeChanged extends PlayerEvent {
  final double volume;

  const VolumeChanged(this.volume);

  @override
  List<Object?> get props => [volume];
}

class PositionUpdated extends PlayerEvent {
  final Duration position;

  const PositionUpdated(this.position);

  @override
  List<Object?> get props => [position];
}

class AudioStateChanged extends PlayerEvent {
  final AudioEngineState state;

  const AudioStateChanged(this.state);

  @override
  List<Object?> get props => [state];
}

class TrackCompleted extends PlayerEvent {
  const TrackCompleted();
}

// ── State ──

class PlayerState extends Equatable {
  final PlayerStatus status;
  final AudioTrack? currentTrack;
  final Playlist playlist;
  final Duration position;
  final Duration? duration;
  final double volume;
  final String? errorMessage;

  const PlayerState({
    this.status = PlayerStatus.idle,
    this.currentTrack,
    this.playlist = const Playlist(),
    this.position = Duration.zero,
    this.duration,
    this.volume = 1.0,
    this.errorMessage,
  });

  bool get hasNext => playlist.hasNext;
  bool get hasPrevious => playlist.hasPrevious;

  PlayerState copyWith({
    PlayerStatus? status,
    AudioTrack? currentTrack,
    Playlist? playlist,
    Duration? position,
    Duration? duration,
    double? volume,
    String? errorMessage,
    bool clearTrack = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      playlist: playlist ?? this.playlist,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentTrack,
        playlist,
        position,
        duration,
        volume,
        errorMessage,
      ];
}

enum PlayerStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  error,
}

// ── BLoC ──

class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  final SessionManager sessionManager;
  final Logger _logger;
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;

  PlayerBloc({required this.sessionManager, Logger? logger})
      : _logger = logger ?? Logger(),
        super(const PlayerState()) {
    on<LoadTrackRequested>(_onLoadTrack);
    on<AddToQueueRequested>(_onAddToQueue);
    on<RemoveFromQueueRequested>(_onRemoveFromQueue);
    on<ClearQueueRequested>(_onClearQueue);
    on<PlayRequested>(_onPlay);
    on<PauseRequested>(_onPause);
    on<ResumeRequested>(_onResume);
    on<StopRequested>(_onStop);
    on<SkipNextRequested>(_onSkipNext);
    on<SkipPreviousRequested>(_onSkipPrevious);
    on<SeekRequested>(_onSeek);
    on<VolumeChanged>(_onVolumeChanged);
    on<PositionUpdated>(_onPositionUpdated);
    on<AudioStateChanged>(_onAudioStateChanged);
    on<TrackCompleted>(_onTrackCompleted);

    // Listen to audio engine state (single subscription)
    _stateSub = sessionManager.audioEngine.stateStream.listen((audioState) {
      add(AudioStateChanged(audioState));
      // Detect track completion: state goes to idle while we were playing
      if (audioState == AudioEngineState.idle &&
          state.status == PlayerStatus.playing) {
        add(const TrackCompleted());
      }
    });

    _positionSub =
        sessionManager.audioEngine.positionStream.listen((position) {
      add(PositionUpdated(position));
    });
  }

  Future<void> _onLoadTrack(
    LoadTrackRequested event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(status: PlayerStatus.loading, errorMessage: null));
    try {
      await sessionManager.audioEngine.loadTrack(event.track);

      // Wait a bit for duration to be available
      await Future.delayed(const Duration(milliseconds: 500));
      final duration = sessionManager.audioEngine.duration;

      // Create a new playlist with this track as the only item
      final playlist = Playlist(tracks: [event.track], currentIndex: 0);

      emit(state.copyWith(
        currentTrack: event.track,
        playlist: playlist,
        status: PlayerStatus.paused,
        duration: duration,
        position: Duration.zero,
      ));
    } catch (e) {
      _logger.e('Failed to load track: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Impossible de charger le fichier: $e',
      ));
    }
  }

  void _onAddToQueue(
    AddToQueueRequested event,
    Emitter<PlayerState> emit,
  ) {
    final newPlaylist = state.playlist.addTrack(event.track);
    emit(state.copyWith(playlist: newPlaylist));
    _logger.i('Added to queue: ${event.track.title} (${newPlaylist.length} tracks)');
  }

  void _onRemoveFromQueue(
    RemoveFromQueueRequested event,
    Emitter<PlayerState> emit,
  ) {
    final newPlaylist = state.playlist.removeTrack(event.index);
    emit(state.copyWith(
      playlist: newPlaylist,
      currentTrack: newPlaylist.currentTrack,
    ));
  }

  void _onClearQueue(
    ClearQueueRequested event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(
      playlist: const Playlist(),
      clearTrack: true,
      status: PlayerStatus.idle,
    ));
  }

  Future<void> _onPlay(
    PlayRequested event,
    Emitter<PlayerState> emit,
  ) async {
    final track = state.currentTrack;
    if (track == null) {
      emit(state.copyWith(errorMessage: 'Aucun morceau sélectionné'));
      return;
    }

    try {
      if (sessionManager.role == DeviceRole.host) {
        // Host: play locally and broadcast to slaves
        await sessionManager.playTrack(track);
      } else {
        // Solo play or slave: just play locally
        await sessionManager.audioEngine.play();
      }
      emit(state.copyWith(status: PlayerStatus.playing, errorMessage: null));
    } catch (e) {
      _logger.e('Play failed: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Erreur de lecture: $e',
      ));
    }
  }

  Future<void> _onPause(
    PauseRequested event,
    Emitter<PlayerState> emit,
  ) async {
    if (sessionManager.role == DeviceRole.host) {
      await sessionManager.pausePlayback();
    } else {
      await sessionManager.audioEngine.pause();
    }
    emit(state.copyWith(status: PlayerStatus.paused));
  }

  Future<void> _onResume(
    ResumeRequested event,
    Emitter<PlayerState> emit,
  ) async {
    if (sessionManager.role == DeviceRole.host) {
      await sessionManager.resumePlayback();
    } else {
      await sessionManager.audioEngine.play();
    }
    emit(state.copyWith(status: PlayerStatus.playing));
  }

  Future<void> _onStop(
    StopRequested event,
    Emitter<PlayerState> emit,
  ) async {
    await sessionManager.audioEngine.stop();
    emit(state.copyWith(status: PlayerStatus.idle, position: Duration.zero));
  }

  Future<void> _onSkipNext(
    SkipNextRequested event,
    Emitter<PlayerState> emit,
  ) async {
    final nextPlaylist = state.playlist.skipNext();
    if (nextPlaylist == null) {
      _logger.w('No next track in queue');
      return;
    }

    final nextTrack = nextPlaylist.currentTrack!;
    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: nextPlaylist,
      currentTrack: nextTrack,
      position: Duration.zero,
    ));

    try {
      await sessionManager.audioEngine.loadTrack(nextTrack);
      await Future.delayed(const Duration(milliseconds: 300));
      final duration = sessionManager.audioEngine.duration;

      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.playTrack(nextTrack);
      } else {
        await sessionManager.audioEngine.play();
      }

      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: duration,
        position: Duration.zero,
      ));
    } catch (e) {
      _logger.e('Skip next failed: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Erreur lors du passage au morceau suivant: $e',
      ));
    }
  }

  Future<void> _onSkipPrevious(
    SkipPreviousRequested event,
    Emitter<PlayerState> emit,
  ) async {
    // If more than 3 seconds into the track, restart it instead of going to previous
    if (state.position.inSeconds > 3) {
      await sessionManager.audioEngine.seek(Duration.zero);
      emit(state.copyWith(position: Duration.zero));
      return;
    }

    final prevPlaylist = state.playlist.skipPrevious();
    if (prevPlaylist == null) {
      // At the beginning, just restart current track
      await sessionManager.audioEngine.seek(Duration.zero);
      emit(state.copyWith(position: Duration.zero));
      return;
    }

    final prevTrack = prevPlaylist.currentTrack!;
    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: prevPlaylist,
      currentTrack: prevTrack,
      position: Duration.zero,
    ));

    try {
      await sessionManager.audioEngine.loadTrack(prevTrack);
      await Future.delayed(const Duration(milliseconds: 300));
      final duration = sessionManager.audioEngine.duration;

      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.playTrack(prevTrack);
      } else {
        await sessionManager.audioEngine.play();
      }

      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: duration,
        position: Duration.zero,
      ));
    } catch (e) {
      _logger.e('Skip previous failed: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Erreur lors du passage au morceau précédent: $e',
      ));
    }
  }

  Future<void> _onSeek(
    SeekRequested event,
    Emitter<PlayerState> emit,
  ) async {
    await sessionManager.audioEngine.seek(event.position);
    emit(state.copyWith(position: event.position));
  }

  Future<void> _onVolumeChanged(
    VolumeChanged event,
    Emitter<PlayerState> emit,
  ) async {
    await sessionManager.audioEngine.setVolume(event.volume);
    emit(state.copyWith(volume: event.volume));
  }

  void _onPositionUpdated(
    PositionUpdated event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(position: event.position));
  }

  void _onAudioStateChanged(
    AudioStateChanged event,
    Emitter<PlayerState> emit,
  ) {
    final duration = sessionManager.audioEngine.duration;

    switch (event.state) {
      case AudioEngineState.idle:
        emit(state.copyWith(status: PlayerStatus.idle, duration: duration));
        break;
      case AudioEngineState.loading:
        emit(state.copyWith(status: PlayerStatus.loading));
        break;
      case AudioEngineState.buffering:
        emit(state.copyWith(status: PlayerStatus.buffering, duration: duration));
        break;
      case AudioEngineState.playing:
        emit(state.copyWith(status: PlayerStatus.playing, duration: duration));
        break;
      case AudioEngineState.paused:
        emit(state.copyWith(status: PlayerStatus.paused, duration: duration));
        break;
      case AudioEngineState.error:
        emit(state.copyWith(
          status: PlayerStatus.error,
          errorMessage: 'Erreur de lecture',
        ));
        break;
    }
  }

  /// Auto-advance to next track when current one finishes.
  Future<void> _onTrackCompleted(
    TrackCompleted event,
    Emitter<PlayerState> emit,
  ) async {
    _logger.i('Track completed, checking for next...');
    final nextPlaylist = state.playlist.skipNext();
    if (nextPlaylist != null) {
      _logger.i('Auto-advancing to next track');
      add(const SkipNextRequested());
    } else {
      _logger.i('No more tracks in queue, stopping');
      emit(state.copyWith(status: PlayerStatus.idle, position: Duration.zero));
    }
  }

  @override
  Future<void> close() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    return super.close();
  }
}
