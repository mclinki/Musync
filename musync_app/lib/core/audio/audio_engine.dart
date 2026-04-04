import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart' as asession;
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../models/models.dart';

/// Audio playback state.
enum AudioEngineState {
  idle,
  loading,
  buffering,
  playing,
  paused,
  error,
}

/// Core audio engine that manages playback.
class AudioEngine {
  final Logger _logger;
  final ja.AudioPlayer _player;
  asession.AudioSession? _audioSession;

  final StreamController<AudioEngineState> _stateController =
      StreamController.broadcast();
  final StreamController<Duration> _positionController =
      StreamController.broadcast();

  AudioEngineState _state = AudioEngineState.idle;
  AudioTrack? _currentTrack;
  Timer? _positionTimer;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _interruptionSub;

  // Pre-loaded audio source for faster playback
  ja.AudioSource? _preloadedSource;

  // Track if we were playing before an interruption
  bool _wasPlayingBeforeInterruption = false;
  // MED-001 fix: Track which audio was playing before interruption
  AudioTrack? _trackBeforeInterruption;

  AudioEngine({Logger? logger})
      : _logger = logger ?? Logger(),
        _player = ja.AudioPlayer(
          // Configure for low latency
        );

  // ── Public API ──

  AudioEngineState get state => _state;
  Stream<AudioEngineState> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;
  AudioTrack? get currentTrack => _currentTrack;

  /// Initialize the audio engine.
  Future<void> initialize() async {
    try {
      _audioSession = await asession.AudioSession.instance;
      await _audioSession!.configure(const asession.AudioSessionConfiguration(
        avAudioSessionCategory: asession.AVAudioSessionCategory.playback,
        avAudioSessionMode: asession.AVAudioSessionMode.defaultMode,
        androidAudioAttributes: asession.AndroidAudioAttributes(
          contentType: asession.AndroidAudioContentType.music,
          usage: asession.AndroidAudioUsage.media,
          flags: asession.AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType: asession.AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));

      _playerStateSub = _player.playerStateStream.listen((playerState) {
        final newState = _mapPlayerState(playerState);
        if (newState != _state) {
          _state = newState;
          if (!_stateController.isClosed) {
            _stateController.add(_state);
          }
          _logger.d('Audio state: $_state');
        }
      });

      // Listen to audio interruptions (phone calls, alarms, etc.)
      _interruptionSub = _audioSession!.interruptionEventStream.listen((event) {
        _handleInterruption(event);
      });

      _positionTimer = Timer.periodic(
        const Duration(milliseconds: AppConstants.positionUpdateIntervalMs),
        (_) {
          if (_player.playing && !_positionController.isClosed) {
            _positionController.add(_player.position);
          }
        },
      );

      _logger.i('Audio engine initialized');
    } catch (e) {
      _logger.e('Failed to initialize audio engine: $e');
      _setState(AudioEngineState.error);
    }
  }

  /// Load a track for playback.
  /// Waits for the player to be ready before returning.
  Future<void> loadTrack(AudioTrack track) async {
    _logger.i('Loading track: ${track.title} (${track.source})');
    _setState(AudioEngineState.loading);

    try {
      if (track.sourceType == AudioSourceType.localFile) {
        final file = File(track.source);
        if (!await file.exists()) {
          throw Exception('File not found: ${track.source}');
        }
        _logger.d('Loading local file: ${track.source}');
        await _player.setFilePath(track.source);
      } else {
        _logger.d('Loading URL: ${track.source}');
        await _player.setUrl(track.source);
      }

      _currentTrack = track;

      // BUG-7 FIX: Wait for player to be fully ready (not buffering/loading)
      // just_audio may still be in buffering state right after setFilePath returns
      if (_player.processingState == ja.ProcessingState.buffering ||
          _player.processingState == ja.ProcessingState.loading) {
        _logger.d('Waiting for player to be ready...');
        await _player.playerStateStream.firstWhere(
          (s) => s.processingState == ja.ProcessingState.ready ||
                 s.processingState == ja.ProcessingState.completed,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _logger.w('Timed out waiting for player ready state');
            return _player.playerState;
          },
        );
      }

      _setState(AudioEngineState.paused);
      _logger.i('Track loaded and ready: ${track.title}');
    } catch (e) {
      _logger.e('Failed to load track: $e');
      _setState(AudioEngineState.error);
      rethrow;
    }
  }

  /// Preload a track without playing it.
  /// This reduces latency when play() is called later.
  Future<void> preloadTrack(AudioTrack track) async {
    _logger.i('Preloading track: ${track.title}');

    try {
      if (track.sourceType == AudioSourceType.localFile) {
        final file = File(track.source);
        if (!await file.exists()) {
          _logger.w('Cannot preload: file not found: ${track.source}');
          return;
        }
        _preloadedSource = ja.AudioSource.uri(Uri.file(track.source));
      } else {
        _preloadedSource = ja.AudioSource.uri(Uri.parse(track.source));
      }

      _logger.i('Track preloaded: ${track.title}');
    } catch (e) {
      _logger.w('Preload failed (non-critical): $e');
      _preloadedSource = null;
    }
  }

  /// Load a preloaded track for immediate playback.
  /// Falls back to regular loadTrack if not preloaded.
  /// Includes retry logic for connection errors (CRASH-7 fix).
  Future<void> loadPreloaded(AudioTrack track) async {
    if (_preloadedSource != null) {
      _logger.i('Loading preloaded track: ${track.title}');
      _setState(AudioEngineState.loading);

      try {
        await _player.setAudioSource(_preloadedSource!).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Audio source load timed out');
          },
        );
        _currentTrack = track;
        _preloadedSource = null;
        _logger.i('Preloaded track loaded successfully');
      } catch (e) {
        _logger.w('Failed to load preloaded source, falling back to regular load: $e');
        _preloadedSource = null;
        // Fallback with retry
        await _loadTrackWithRetry(track);
      }
    } else {
      await _loadTrackWithRetry(track);
    }
  }

  /// Load track with retry logic for connection errors.
  Future<void> _loadTrackWithRetry(AudioTrack track, {int maxRetries = 2}) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await loadTrack(track);
        return; // Success
      } catch (e) {
        if (attempt < maxRetries && _isRetryableError(e)) {
          _logger.w('Retry ${attempt + 1}/$maxRetries for track load: $e');
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        } else {
          rethrow;
        }
      }
    }
  }

  /// Check if an error is retryable (connection errors, timeouts).
  bool _isRetryableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('connection aborted') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('timeout') ||
        errorStr.contains('socket') ||
        errorStr.contains('errno');
  }

  /// Play immediately.
  Future<void> play() async {
    _logger.i('Playing...');
    await _player.play();
  }

  /// Pause playback.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Stop playback and reset position.
  Future<void> stop() async {
    // Guard: don't stop if already idle (prevents native crash on Windows)
    if (_state == AudioEngineState.idle) return;
    try {
      await _player.stop();
    } catch (e) {
      _logger.w('Stop failed (non-critical): $e');
    }
    _currentTrack = null;
    _setState(AudioEngineState.idle);
  }

  /// Seek to a specific position.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set volume (0.0 to 1.0).
  /// NOTE: System volume is now handled by SystemVolumeService.
  /// This method is kept for backward compatibility but does nothing.
  /// just_audio volume is kept at 1.0 (max) so system volume is the only control.
  Future<void> setVolume(double volume) async {
    // Volume is now controlled at the system level by SystemVolumeService.
    // just_audio volume stays at 1.0 (max) — no-op here.
  }

  /// Dispose resources.
  Future<void> dispose() async {
    // Cancel timer FIRST to prevent callbacks firing on closed controllers
    _positionTimer?.cancel();
    _positionTimer = null;

    await _playerStateSub?.cancel();
    await _interruptionSub?.cancel();
    await _player.dispose();

    // Close controllers AFTER all producers are stopped
    if (!_stateController.isClosed) await _stateController.close();
    if (!_positionController.isClosed) await _positionController.close();
    _logger.i('Audio engine disposed');
  }

  // ── Internal ──

  /// Handle audio interruptions (phone calls, alarms, etc.).
  void _handleInterruption(asession.AudioInterruptionEvent event) {
    if (event.begin) {
      // Interruption started
      _logger.i('Audio interruption began: ${event.type}');
      _wasPlayingBeforeInterruption = _player.playing;
      // MED-001 fix: Remember which track was playing
      _trackBeforeInterruption = _currentTrack;

      if (event.type == asession.AudioInterruptionType.pause ||
          event.type == asession.AudioInterruptionType.unknown) {
        // Pause playback for pause-type interruptions
        _player.pause();
        _logger.d('Paused due to interruption');
      }
      // For duck-type interruptions, we could reduce volume instead
    } else {
      // Interruption ended
      _logger.i('Audio interruption ended: ${event.type}');

      if (event.type == asession.AudioInterruptionType.pause ||
          event.type == asession.AudioInterruptionType.unknown) {
        // MED-001 fix: Only resume if the same track is still loaded
        if (_wasPlayingBeforeInterruption && _currentTrack == _trackBeforeInterruption) {
          _player.play();
          _logger.d('Resumed after interruption');
        } else if (_wasPlayingBeforeInterruption && _currentTrack != _trackBeforeInterruption) {
          _logger.d('Skipping resume: track changed during interruption');
        }
      }
    }
  }

  AudioEngineState _mapPlayerState(ja.PlayerState playerState) {
    if (playerState.processingState == ja.ProcessingState.loading ||
        playerState.processingState == ja.ProcessingState.buffering) {
      return AudioEngineState.buffering;
    }
    if (playerState.playing) {
      return AudioEngineState.playing;
    }
    if (playerState.processingState == ja.ProcessingState.completed) {
      return AudioEngineState.idle;
    }
    return AudioEngineState.paused;
  }

  void _setState(AudioEngineState newState) {
    if (newState != _state) {
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }
    }
  }
}
