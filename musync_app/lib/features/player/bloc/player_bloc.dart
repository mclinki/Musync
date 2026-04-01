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

class SyncQualityUpdated extends PlayerEvent {
  final String qualityLabel;
  final double offsetMs;

  const SyncQualityUpdated({required this.qualityLabel, required this.offsetMs});

  @override
  List<Object?> get props => [qualityLabel, offsetMs];
}

class _SyncingFilesChanged extends PlayerEvent {
  final Set<String> files;
  const _SyncingFilesChanged(this.files);
  @override
  List<Object?> get props => [files];
}

class _SyncingFileProgress extends PlayerEvent {
  final String fileName;
  final bool isComplete;
  const _SyncingFileProgress({required this.fileName, required this.isComplete});
  @override
  List<Object?> get props => [fileName, isComplete];
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
  final String? syncQualityLabel;
  final double? syncOffsetMs;
  /// Set of filenames currently being synced to slaves (host) or received (guest).
  final Set<String> syncingFiles;

  const PlayerState({
    this.status = PlayerStatus.idle,
    this.currentTrack,
    this.playlist = const Playlist(),
    this.position = Duration.zero,
    this.duration,
    this.volume = 1.0,
    this.errorMessage,
    this.syncQualityLabel,
    this.syncOffsetMs,
    this.syncingFiles = const {},
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
    String? syncQualityLabel,
    double? syncOffsetMs,
    Set<String>? syncingFiles,
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
      syncQualityLabel: syncQualityLabel ?? this.syncQualityLabel,
      syncOffsetMs: syncOffsetMs ?? this.syncOffsetMs,
      syncingFiles: syncingFiles ?? this.syncingFiles,
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
        syncQualityLabel,
        syncOffsetMs,
        syncingFiles,
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
  final FirebaseService _firebase;
  final Logger _logger;
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _clientEventSub;
  StreamSubscription? _syncQualitySub;
  StreamSubscription? _fileTransferSub;

  PlayerBloc({required this.sessionManager, FirebaseService? firebase, Logger? logger})
      : _firebase = firebase ?? FirebaseService(),
        _logger = logger ?? Logger(),
        super(const PlayerState()) {
    on<LoadTrackRequested>(_onLoadTrack);
    on<AddToQueueRequested>(_onAddToQueue);
    on<RemoveFromQueueRequested>(_onRemoveFromQueue);
    on<ClearQueueRequested>(_onClearQueue);
    on<PlayRequested>(_onPlay);
    on<PauseRequested>(_onPause);
    on<StopRequested>(_onStop);
    on<SkipNextRequested>(_onSkipNext);
    on<SkipPreviousRequested>(_onSkipPrevious);
    on<SeekRequested>(_onSeek);
    on<VolumeChanged>(_onVolumeChanged);
    on<PositionUpdated>(_onPositionUpdated);
    on<AudioStateChanged>(_onAudioStateChanged);
    on<TrackCompleted>(_onTrackCompleted);
    on<SyncQualityUpdated>(_onSyncQualityUpdated);

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

    // Listen to host commands (for guest mode)
    _clientEventSub = sessionManager.clientEvents?.listen((event) {
      if (event.type == ClientEventType.skipNextCommand) {
        _logger.i('Host triggered skip next');
        add(const SkipNextRequested());
      } else if (event.type == ClientEventType.skipPrevCommand) {
        _logger.i('Host triggered skip prev');
        add(const SkipPreviousRequested());
      } else if (event.type == ClientEventType.playlistUpdateCommand) {
        // Playlist update handled by DiscoveryBloc
        _logger.d('Playlist update received');
      }
    });

    // Listen to sync quality updates
    _syncQualitySub = sessionManager.syncQualityStream.listen((update) {
      add(SyncQualityUpdated(
        qualityLabel: update.qualityLabel,
        offsetMs: update.offsetMs,
      ));
    });

    // Listen to file transfer progress for syncing indicators
    _fileTransferSub = sessionManager.fileTransfer.progressStream.listen((progress) {
      add(_SyncingFileProgress(
        fileName: progress.fileName,
        isComplete: progress.percentage >= 1.0,
      ));
    });
    on<_SyncingFileProgress>((event, emit) {
      final syncing = Set<String>.from(state.syncingFiles);
      if (event.isComplete) {
        syncing.remove(event.fileName);
      } else {
        syncing.add(event.fileName);
      }
      emit(state.copyWith(syncingFiles: syncing));
    });
    on<_SyncingFilesChanged>((event, emit) {
      emit(state.copyWith(syncingFiles: event.files));
    });
  }

  Future<void> _onLoadTrack(
    LoadTrackRequested event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(status: PlayerStatus.loading, errorMessage: null));
    try {
      await sessionManager.audioEngine.loadTrack(event.track);

      final duration = await _waitForDuration();

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

  Future<void> _onAddToQueue(
    AddToQueueRequested event,
    Emitter<PlayerState> emit,
  ) async {
    final newPlaylist = state.playlist.addTrack(event.track);
    emit(state.copyWith(playlist: newPlaylist));
    _logger.i('Added to queue: ${event.track.title} (${newPlaylist.length} tracks)');

    // Auto-sync to slaves if host and there are connected slaves
    if (sessionManager.role == DeviceRole.host &&
        event.track.sourceType == AudioSourceType.localFile) {
      final fileName = event.track.source.split('/').last.split('\\').last;
      // Use local variable instead of reading state after emit
      final syncing = Set<String>.from(state.syncingFiles)..add(fileName);
      emit(state.copyWith(syncingFiles: syncing));
      _logger.i('Auto-syncing track to slaves: $fileName');
      try {
        await sessionManager.syncTrackToSlaves(event.track);
        syncing.remove(fileName);
        emit(state.copyWith(syncingFiles: syncing));
        _logger.i('Track synced to slaves: $fileName');
      } catch (e) {
        _logger.e('Failed to sync track to slaves: $e');
        syncing.remove(fileName);
        emit(state.copyWith(syncingFiles: syncing));
      }
    }
  }

  Future<void> _onRemoveFromQueue(
    RemoveFromQueueRequested event,
    Emitter<PlayerState> emit,
  ) async {
    final removedIndex = event.index;
    final wasCurrentTrack = removedIndex == state.playlist.currentIndex;
    final wasActive = state.status == PlayerStatus.playing ||
        state.status == PlayerStatus.paused;

    final newPlaylist = state.playlist.removeTrack(event.index);

    if (wasCurrentTrack && wasActive) {
      // Removed the currently active track — stop playback
      try {
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.pausePlayback();
        }
        await sessionManager.audioEngine.stop();
      } catch (e) {
        _logger.w('Error stopping after track removal: $e');
      }
      emit(state.copyWith(
        playlist: newPlaylist,
        currentTrack: newPlaylist.currentTrack,
        status: newPlaylist.isEmpty ? PlayerStatus.idle : PlayerStatus.paused,
        position: Duration.zero,
      ));
    } else {
      emit(state.copyWith(
        playlist: newPlaylist,
        currentTrack: newPlaylist.currentTrack,
      ));
    }
  }

  Future<void> _onClearQueue(
    ClearQueueRequested event,
    Emitter<PlayerState> emit,
  ) async {
    try {
      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.pausePlayback();
      }
      await sessionManager.audioEngine.stop();
    } catch (e) {
      _logger.w('Error stopping on clear: $e');
    }
    emit(state.copyWith(
      playlist: const Playlist(),
      clearTrack: true,
      status: PlayerStatus.idle,
      position: Duration.zero,
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
      // Determine if this is a true resume (same track already loaded and paused)
      // or a fresh play (track loaded but never played, or different track)
      final audioTrack = sessionManager.audioEngine.currentTrack;
      final isTrueResume = state.status == PlayerStatus.paused &&
          audioTrack != null &&
          audioTrack.source == track.source;

      if (isTrueResume) {
        // Resume from pause
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.resumePlayback();
        } else {
          await sessionManager.audioEngine.play();
        }
      } else {
        // Fresh play: sync to slaves and play from start
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.playTrack(track, playlist: state.playlist);
        } else {
          await sessionManager.audioEngine.play();
        }
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
    try {
      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.pausePlayback();
      } else {
        await sessionManager.audioEngine.pause();
      }
      emit(state.copyWith(status: PlayerStatus.paused));
    } catch (e, stack) {
      _logger.e('Pause failed: $e');
      _firebase.recordError(e, stack, reason: 'pause');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Erreur lors de la pause: $e',
      ));
    }
  }

  Future<void> _onStop(
    StopRequested event,
    Emitter<PlayerState> emit,
  ) async {
    try {
      // Broadcast pause to slaves before stopping locally
      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.pausePlayback();
      }
      await sessionManager.audioEngine.stop();
      emit(state.copyWith(status: PlayerStatus.idle, position: Duration.zero));
    } catch (e, stack) {
      _logger.e('Stop failed: $e');
      _firebase.recordError(e, stack, reason: 'stop');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Erreur lors de l\'arrêt: $e',
      ));
    }
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

    // Guest mode: pause current audio and set loading, wait for host's playCommand
    if (sessionManager.role == DeviceRole.slave) {
      _logger.i('Guest skip next: waiting for host play command');
      try {
        await sessionManager.audioEngine.pause();
      } catch (_) {}
      emit(state.copyWith(status: PlayerStatus.loading));
      return;
    }

    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: nextPlaylist,
      currentTrack: nextTrack,
      position: Duration.zero,
    ));

    try {
      await sessionManager.audioEngine.loadTrack(nextTrack);
      final duration = await _waitForDuration();

      await sessionManager.playTrack(nextTrack, playlist: nextPlaylist);

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
    // If more than skipPreviousRestartThresholdSeconds into the track, restart it instead of going to previous
    if (state.position.inSeconds > AppConstants.skipPreviousRestartThresholdSeconds) {
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

    // Guest mode: pause current audio and set loading, wait for host's playCommand
    if (sessionManager.role == DeviceRole.slave) {
      _logger.i('Guest skip prev: waiting for host play command');
      try {
        await sessionManager.audioEngine.pause();
      } catch (_) {}
      emit(state.copyWith(status: PlayerStatus.loading));
      return;
    }

    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: prevPlaylist,
      currentTrack: prevTrack,
      position: Duration.zero,
    ));

    try {
      await sessionManager.audioEngine.loadTrack(prevTrack);
      final duration = await _waitForDuration();

      await sessionManager.playTrack(prevTrack, playlist: prevPlaylist);

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
    try {
      await sessionManager.audioEngine.seek(event.position);
      emit(state.copyWith(position: event.position));
    } catch (e, stack) {
      _logger.e('Seek failed: $e');
      _firebase.recordError(e, stack, reason: 'seek');
      emit(state.copyWith(
        errorMessage: 'Erreur lors du déplacement: $e',
      ));
    }
  }

  Future<void> _onVolumeChanged(
    VolumeChanged event,
    Emitter<PlayerState> emit,
  ) async {
    try {
      await sessionManager.audioEngine.setVolume(event.volume);
      emit(state.copyWith(volume: event.volume));
    } catch (e, stack) {
      _logger.e('Set volume failed: $e');
      _firebase.recordError(e, stack, reason: 'volumeChanged');
      emit(state.copyWith(
        errorMessage: 'Erreur lors du changement de volume: $e',
      ));
    }
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

  void _onSyncQualityUpdated(
    SyncQualityUpdated event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(
      syncQualityLabel: event.qualityLabel,
      syncOffsetMs: event.offsetMs,
    ));
  }

  /// Waits for the audio engine's duration to become available after loading.
  /// Listens on the durationStream instead of using an arbitrary delay.
  /// Falls back to reading duration directly after timeout.
  Future<Duration?> _waitForDuration({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final engine = sessionManager.audioEngine;

    // If duration is already available, return immediately
    if (engine.duration != null) return engine.duration;

    // Otherwise wait for the stream to emit a non-null duration
    try {
      return await engine.durationStream
          .firstWhere((d) => d != null && d > Duration.zero)
          .timeout(timeout);
    } on TimeoutException {
      _logger.w('Timed out waiting for duration, using fallback');
      return engine.duration;
    }
  }

  @override
  Future<void> close() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _clientEventSub?.cancel();
    _syncQualitySub?.cancel();
    _fileTransferSub?.cancel();
    return super.close();
  }
}
