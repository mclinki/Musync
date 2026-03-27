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

// ── State ──

class PlayerState extends Equatable {
  final PlayerStatus status;
  final AudioTrack? currentTrack;
  final Duration position;
  final Duration? duration;
  final double volume;
  final String? errorMessage;

  const PlayerState({
    this.status = PlayerStatus.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1.0,
    this.errorMessage,
  });

  PlayerState copyWith({
    PlayerStatus? status,
    AudioTrack? currentTrack,
    Duration? position,
    Duration? duration,
    double? volume,
    String? errorMessage,
  }) {
    return PlayerState(
      status: status ?? this.status,
      currentTrack: currentTrack ?? this.currentTrack,
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
    on<PlayRequested>(_onPlay);
    on<PauseRequested>(_onPause);
    on<ResumeRequested>(_onResume);
    on<StopRequested>(_onStop);
    on<SeekRequested>(_onSeek);
    on<VolumeChanged>(_onVolumeChanged);
    on<PositionUpdated>(_onPositionUpdated);
    on<AudioStateChanged>(_onAudioStateChanged);

    // Listen to audio engine
    _stateSub = sessionManager.audioEngine.stateStream.listen((state) {
      add(AudioStateChanged(state));
    });

    _positionSub = sessionManager.audioEngine.positionStream.listen((position) {
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
      
      emit(state.copyWith(
        currentTrack: event.track,
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
    emit(const PlayerState());
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

  @override
  Future<void> close() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    return super.close();
  }
}
