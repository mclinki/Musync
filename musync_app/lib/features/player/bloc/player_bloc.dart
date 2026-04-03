import 'dart:async';
import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/core.dart';
import '../../../core/utils/format.dart';

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

class ConnectedDevicesUpdated extends PlayerEvent {
  final List<ConnectedDeviceInfo> devices;
  const ConnectedDevicesUpdated(this.devices);
  @override
  List<Object?> get props => [devices];
}

class _AllGuestsReadyUpdated extends PlayerEvent {
  final bool ready;
  const _AllGuestsReadyUpdated(this.ready);
  @override
  List<Object?> get props => [ready];
}

class _LoadSavedPlaylist extends PlayerEvent {
  const _LoadSavedPlaylist();
}

class ToggleShuffleRequested extends PlayerEvent {
  const ToggleShuffleRequested();
}

class ToggleRepeatRequested extends PlayerEvent {
  const ToggleRepeatRequested();
}

class VolumeRemoteChanged extends PlayerEvent {
  final double volume;
  const VolumeRemoteChanged(this.volume);
  @override
  List<Object?> get props => [volume];
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
  /// Connected slave devices with sync info (host only).
  final List<ConnectedDeviceInfo> connectedDevices;
  /// Whether all connected guests have finished loading the current track.
  final bool allGuestsReady;
  /// Current repeat mode (off, one, all).
  final RepeatMode repeatMode;
  /// Whether shuffle mode is active.
  final bool isShuffled;

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
    this.connectedDevices = const [],
    this.allGuestsReady = false,
    this.repeatMode = RepeatMode.off,
    this.isShuffled = false,
  });

  bool get hasNext => playlist.hasNext;
  bool get hasPrevious => playlist.hasPrevious;

  PlayerState copyWith({
    PlayerStatus? status,
    AudioTrack? currentTrack,
    bool clearCurrentTrack = false,
    Playlist? playlist,
    Duration? position,
    Duration? duration,
    double? volume,
    String? errorMessage,
    String? syncQualityLabel,
    double? syncOffsetMs,
    Set<String>? syncingFiles,
    List<ConnectedDeviceInfo>? connectedDevices,
    bool? allGuestsReady,
    RepeatMode? repeatMode,
    bool? isShuffled,
  }) {
    return PlayerState(
      status: status ?? this.status,
      currentTrack: clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      playlist: playlist ?? this.playlist,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      errorMessage: errorMessage,
      syncQualityLabel: syncQualityLabel ?? this.syncQualityLabel,
      syncOffsetMs: syncOffsetMs ?? this.syncOffsetMs,
      syncingFiles: syncingFiles ?? this.syncingFiles,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      allGuestsReady: allGuestsReady ?? this.allGuestsReady,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffled: isShuffled ?? this.isShuffled,
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
        connectedDevices,
        allGuestsReady,
        repeatMode,
        isShuffled,
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
  /// HIGH-008 fix: Direct AudioEngine injection (Law of Demeter).
  final AudioEngine audioEngine;
  final FirebaseService _firebase;
  final Logger _logger;
  final SharedPreferences? _prefs;
  bool _isClosed = false;
  StreamSubscription? _stateSub;
  StreamSubscription? _sessionStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _clientEventSub;
  StreamSubscription? _syncQualitySub;
  StreamSubscription? _fileTransferSub;
  StreamSubscription? _connectedDevicesSub;
  StreamSubscription? _allGuestsReadySub;

  PlayerBloc({
    required this.sessionManager,
    required this.audioEngine,
    FirebaseService? firebase,
    Logger? logger,
    SharedPreferences? prefs,
  })  : _firebase = firebase ?? FirebaseService(),
        _logger = logger ?? Logger(),
        _prefs = prefs,
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
    on<ConnectedDevicesUpdated>(_onConnectedDevicesUpdated);
    on<_AllGuestsReadyUpdated>(_onAllGuestsReadyUpdated);
    on<_LoadSavedPlaylist>(_onLoadSavedPlaylist);
    on<ToggleShuffleRequested>(_onToggleShuffle);
    on<ToggleRepeatRequested>(_onToggleRepeat);
    on<VolumeRemoteChanged>(_onVolumeRemoteChanged);

    // Listen to audio engine state (single subscription)
    _stateSub = audioEngine.stateStream.listen((audioState) {
      if (_isClosed) return;
      add(AudioStateChanged(audioState));
      // Detect track completion: state goes to idle while we were playing
      if (audioState == AudioEngineState.idle &&
          state.status == PlayerStatus.playing) {
        add(const TrackCompleted());
      }
    });

    _positionSub =
        audioEngine.positionStream.listen((position) {
      if (_isClosed) return;
      add(PositionUpdated(position));
    });

    // Listen to host commands (for guest mode)
    // HIGH-012 fix: Also listen to stateStream to re-subscribe on reconnect
    _clientEventSub = sessionManager.clientEvents?.listen((event) {
      if (_isClosed) return;
      _handleClientEvent(event);
    });

    _sessionStateSub = sessionManager.stateStream.listen((state) {
      if (_isClosed) return;
      // Re-subscribe to clientEvents when joining a new session
      if (state == SessionManagerState.joined) {
        _clientEventSub?.cancel();
        _clientEventSub = sessionManager.clientEvents?.listen((event) {
          if (_isClosed) return;
          _handleClientEvent(event);
        });
        _logger.i('Re-subscribed to clientEvents after session join');
      }
    });

    // Listen to sync quality updates
    _syncQualitySub = sessionManager.syncQualityStream.listen((update) {
      if (_isClosed) return;
      add(SyncQualityUpdated(
        qualityLabel: update.qualityLabel,
        offsetMs: update.offsetMs,
      ));
    });

    // Listen to file transfer progress for syncing indicators
    _fileTransferSub = sessionManager.fileTransfer.progressStream.listen((progress) {
      if (_isClosed) return;
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

    // Listen to connected devices updates (host dashboard)
    _connectedDevicesSub = sessionManager.connectedDevicesStream.listen((devices) {
      if (_isClosed) return;
      add(ConnectedDevicesUpdated(devices));
    });

    // Listen to all guests ready status
    _allGuestsReadySub = sessionManager.allGuestsReadyStream.listen((ready) {
      if (_isClosed) return;
      add(_AllGuestsReadyUpdated(ready));
    });

    // Charger la playlist sauvegardée au démarrage
    add(const _LoadSavedPlaylist());
  }

  void _onLoadSavedPlaylist(
    _LoadSavedPlaylist event,
    Emitter<PlayerState> emit,
  ) {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final playlistJson = prefs.getString('saved_playlist');
      if (playlistJson != null) {
        final playlist = Playlist.fromJson(
          Map<String, dynamic>.from(jsonDecode(playlistJson)),
        );
        if (playlist.tracks.isNotEmpty) {
          emit(state.copyWith(playlist: playlist));
          _logger.i('Loaded saved playlist: ${playlist.length} tracks');
        }
      }
    } catch (e) {
      _logger.w('Failed to load saved playlist: $e');
    }
  }

  /// Sauvegarder la playlist dans SharedPreferences.
  void _savePlaylist() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final jsonStr = jsonEncode(state.playlist.toJson());
      prefs.setString('saved_playlist', jsonStr);
    } catch (e) {
      _logger.w('Failed to save playlist: $e');
    }
  }

  Future<void> _onLoadTrack(
    LoadTrackRequested event,
    Emitter<PlayerState> emit,
  ) async {
    emit(state.copyWith(status: PlayerStatus.loading, errorMessage: null));
    try {
      await audioEngine.loadTrack(event.track);

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
      _savePlaylist();
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
    // If playlist is empty and no track is loaded, load this track as the first one
    if (state.playlist.isEmpty && state.currentTrack == null) {
      emit(state.copyWith(status: PlayerStatus.loading, errorMessage: null));
      try {
        await audioEngine.loadTrack(event.track);
        final duration = await _waitForDuration();
        final playlist = Playlist(tracks: [event.track], currentIndex: 0);
        emit(state.copyWith(
          currentTrack: event.track,
          playlist: playlist,
          status: PlayerStatus.paused,
          duration: duration,
          position: Duration.zero,
        ));
        _savePlaylist();
        _logger.i('Loaded first track from queue add: ${event.track.title}');
      } catch (e) {
        _logger.e('Failed to load first track from queue add: $e');
        emit(state.copyWith(
          status: PlayerStatus.error,
          errorMessage: 'Impossible de charger le fichier: $e',
        ));
      }
      return;
    }

    final newPlaylist = state.playlist.addTrack(event.track);
    emit(state.copyWith(playlist: newPlaylist));
    _savePlaylist();
    _logger.i('Added to queue: ${event.track.title} (${newPlaylist.length} tracks)');

    // Auto-sync to slaves if host and there are connected slaves
    if (sessionManager.role == DeviceRole.host &&
        event.track.sourceType == AudioSourceType.localFile) {
      final fileName = extractFileName(event.track.source);
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
        await audioEngine.stop();
      } catch (e) {
        _logger.w('Error stopping after track removal: $e');
      }
      emit(state.copyWith(
        playlist: newPlaylist,
        currentTrack: newPlaylist.currentTrack,
        status: newPlaylist.isEmpty ? PlayerStatus.idle : PlayerStatus.paused,
        position: Duration.zero,
      ));
      _savePlaylist();
    } else {
      emit(state.copyWith(
        playlist: newPlaylist,
        currentTrack: newPlaylist.currentTrack,
      ));
      _savePlaylist();
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
      await audioEngine.stop();
    } catch (e) {
      _logger.w('Error stopping on clear: $e');
    }
    emit(state.copyWith(
      playlist: const Playlist(),
      clearCurrentTrack: true,
      status: PlayerStatus.idle,
      position: Duration.zero,
    ));
    _savePlaylist();
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
      final audioTrack = audioEngine.currentTrack;
      final isTrueResume = state.status == PlayerStatus.paused &&
          audioTrack != null &&
          audioTrack.source == track.source;

      if (isTrueResume) {
        // Resume from pause
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.resumePlayback();
        } else {
          await audioEngine.play();
          // Notify host that guest resumed (SYNC 2 fix)
          sessionManager.sendToHost(ProtocolMessage.guestResume());
        }
      } else {
        // Fresh play: sync to slaves and play from start
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.playTrack(track, playlist: state.playlist);
        } else {
          await audioEngine.play();
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
        await audioEngine.pause();
        // Notify host that guest paused (SYNC 2 fix)
        final positionMs = audioEngine.position.inMilliseconds;
        sessionManager.sendToHost(ProtocolMessage.guestPause(positionMs: positionMs));
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
      await audioEngine.stop();
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
        await audioEngine.pause();
      } catch (e) {
        _logger.d('Guest skip next pause failed: $e');
      }
      emit(state.copyWith(status: PlayerStatus.loading));
      return;
    }

    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: nextPlaylist,
      currentTrack: nextTrack,
      position: Duration.zero,
    ));
    _savePlaylist();

    try {
      await audioEngine.loadTrack(nextTrack);
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
      await audioEngine.seek(Duration.zero);
      emit(state.copyWith(position: Duration.zero));
      return;
    }

    final prevPlaylist = state.playlist.skipPrevious();
    if (prevPlaylist == null) {
      // At the beginning, just restart current track
      await audioEngine.seek(Duration.zero);
      emit(state.copyWith(position: Duration.zero));
      return;
    }

    final prevTrack = prevPlaylist.currentTrack!;

    // Guest mode: pause current audio and set loading, wait for host's playCommand
    if (sessionManager.role == DeviceRole.slave) {
      _logger.i('Guest skip prev: waiting for host play command');
      try {
        await audioEngine.pause();
      } catch (e) {
        _logger.d('Guest skip prev pause failed: $e');
      }
      emit(state.copyWith(status: PlayerStatus.loading));
      return;
    }

    emit(state.copyWith(
      status: PlayerStatus.loading,
      playlist: prevPlaylist,
      currentTrack: prevTrack,
      position: Duration.zero,
    ));
    _savePlaylist();

    try {
      await audioEngine.loadTrack(prevTrack);
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
      await audioEngine.seek(event.position);
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
      await audioEngine.setVolume(event.volume);
      emit(state.copyWith(volume: event.volume));
      // Broadcast volume to slaves if host
      if (sessionManager.role == DeviceRole.host) {
        await sessionManager.broadcastVolume(event.volume);
      }
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
    final duration = audioEngine.duration;

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
    final playlist = state.playlist;
    final currentIndex = playlist.currentIndex;

    if (playlist.repeatMode == RepeatMode.one) {
      _logger.i('Repeat one: replaying current track');
      emit(state.copyWith(status: PlayerStatus.playing, position: Duration.zero));
      try {
        await audioEngine.seek(Duration.zero);
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.playTrack(
            playlist.tracks[currentIndex],
            playlist: playlist,
          );
        } else {
          await audioEngine.play();
        }
      } catch (e) {
        _logger.e('Repeat one replay failed: $e');
        emit(state.copyWith(status: PlayerStatus.idle));
      }
      return;
    }

    final nextPlaylist = playlist.skipNext();
    if (nextPlaylist != null) {
      _logger.i('Auto-advancing to next track');
      add(const SkipNextRequested());
    } else if (playlist.repeatMode == RepeatMode.all) {
      _logger.i('Repeat all: looping au début');
      final loopedPlaylist = playlist.copyWith(currentIndex: 0);
      final firstTrack = loopedPlaylist.tracks[0];
      emit(state.copyWith(
        playlist: loopedPlaylist,
        currentTrack: firstTrack,
        status: PlayerStatus.loading,
        position: Duration.zero,
      ));
      _savePlaylist();
      try {
        await audioEngine.loadTrack(firstTrack);
        final duration = await _waitForDuration();
        if (sessionManager.role == DeviceRole.host) {
          await sessionManager.playTrack(firstTrack, playlist: loopedPlaylist);
        } else {
          await audioEngine.play();
        }
        emit(state.copyWith(
          status: PlayerStatus.playing,
          duration: duration,
          position: Duration.zero,
        ));
      } catch (e) {
        _logger.e('Repeat all loop failed: $e');
        emit(state.copyWith(status: PlayerStatus.idle, position: Duration.zero));
      }
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

  void _onConnectedDevicesUpdated(
    ConnectedDevicesUpdated event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(connectedDevices: event.devices));
  }

  void _onAllGuestsReadyUpdated(
    _AllGuestsReadyUpdated event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(allGuestsReady: event.ready));
  }

  void _onToggleShuffle(
    ToggleShuffleRequested event,
    Emitter<PlayerState> emit,
  ) {
    if (state.playlist.tracks.length <= 1) return;

    final currentTrack = state.currentTrack;
    final newPlaylist = state.isShuffled
        ? state.playlist.copyWith(isShuffled: false)
        : state.playlist.shuffle();

    if (newPlaylist != null && currentTrack != null) {
      final newIndex = newPlaylist.tracks.indexWhere((t) => t.id == currentTrack.id);
      final adjustedIndex = newIndex >= 0 ? newIndex : 0;
      emit(state.copyWith(
        playlist: newPlaylist.copyWith(currentIndex: adjustedIndex),
        isShuffled: !state.isShuffled,
      ));
      _logger.i('Shuffle ${state.isShuffled ? "disabled" : "enabled"}');
      _savePlaylist();

      if (sessionManager.role == DeviceRole.host) {
        _broadcastPlaylistUpdate();
      }
    } else if (newPlaylist != null) {
      emit(state.copyWith(
        playlist: newPlaylist,
        isShuffled: !state.isShuffled,
      ));
      _logger.i('Shuffle ${state.isShuffled ? "disabled" : "enabled"}');
      _savePlaylist();

      if (sessionManager.role == DeviceRole.host) {
        _broadcastPlaylistUpdate();
      }
    }
  }

  void _onToggleRepeat(
    ToggleRepeatRequested event,
    Emitter<PlayerState> emit,
  ) {
    final newPlaylist = state.playlist.toggleRepeat();
    emit(state.copyWith(playlist: newPlaylist, repeatMode: newPlaylist.repeatMode));
    _logger.i('Repeat mode: ${newPlaylist.repeatMode.name}');
    _savePlaylist();
  }

  void _onVolumeRemoteChanged(
    VolumeRemoteChanged event,
    Emitter<PlayerState> emit,
  ) {
    emit(state.copyWith(volume: event.volume));
    audioEngine.setVolume(event.volume);
    _logger.i('Remote volume set to: ${event.volume}');
  }

  void _broadcastPlaylistUpdate() {
    final playlist = state.playlist;
    sessionManager.broadcastPlaylistUpdate(
      tracks: playlist.tracks.map((t) => {
        'title': t.title,
        'artist': t.artist,
        'source': t.source,
        'sourceType': t.sourceType.name,
      }).toList(),
      currentIndex: playlist.currentIndex,
      repeatMode: playlist.repeatMode.name,
      isShuffled: playlist.isShuffled,
    );
  }

  /// Waits for the audio engine's duration to become available after loading.
  /// Listens on the durationStream instead of using an arbitrary delay.
  /// Falls back to reading duration directly after timeout.
  Future<Duration?> _waitForDuration({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final engine = audioEngine;

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

  /// Handle client events from host (HIGH-012 fix: extracted for re-subscription)
  void _handleClientEvent(ClientEvent event) {
    if (event.type == ClientEventType.skipNextCommand) {
      _logger.i('Host triggered skip next');
      add(const SkipNextRequested());
    } else if (event.type == ClientEventType.skipPrevCommand) {
      _logger.i('Host triggered skip prev');
      add(const SkipPreviousRequested());
    } else if (event.type == ClientEventType.volumeControlCommand) {
      final volume = event.volume ?? 1.0;
      _logger.i('Remote volume command: $volume');
      add(VolumeRemoteChanged(volume));
    } else if (event.type == ClientEventType.playlistUpdateCommand) {
      // Playlist update handled by DiscoveryBloc
      _logger.d('Playlist update received');
    }
  }

  @override
  Future<void> close() {
    _isClosed = true;
    _stateSub?.cancel();
    _sessionStateSub?.cancel();
    _positionSub?.cancel();
    _clientEventSub?.cancel();
    _syncQualitySub?.cancel();
    _fileTransferSub?.cancel();
    _connectedDevicesSub?.cancel();
    _allGuestsReadySub?.cancel();
    return super.close();
  }
}
