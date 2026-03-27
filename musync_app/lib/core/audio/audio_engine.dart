import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart' as asession;
import 'package:logger/logger.dart';
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

  AudioEngine({Logger? logger})
      : _logger = logger ?? Logger(),
        _player = ja.AudioPlayer();

  // ── Public API ──

  AudioEngineState get state => _state;
  Stream<AudioEngineState> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
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

      _player.playerStateStream.listen((playerState) {
        final newState = _mapPlayerState(playerState);
        if (newState != _state) {
          _state = newState;
          _stateController.add(_state);
          _logger.d('Audio state: $_state');
        }
      });

      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) {
          if (_player.playing) {
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
      _logger.i('Track loaded successfully: ${track.title}');
    } catch (e) {
      _logger.e('Failed to load track: $e');
      _setState(AudioEngineState.error);
      rethrow;
    }
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
    await _player.stop();
    _currentTrack = null;
    _setState(AudioEngineState.idle);
  }

  /// Seek to a specific position.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _player.dispose();
    await _stateController.close();
    await _positionController.close();
    _logger.i('Audio engine disposed');
  }

  // ── Internal ──

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
      _stateController.add(_state);
    }
  }
}
