import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

import '../app_constants.dart';
import '../audio/audio_engine.dart';
import '../models/models.dart';
import '../network/websocket_server.dart';
import '../network/websocket_client.dart';
import '../services/file_transfer_service.dart';
import '../services/firebase_service.dart';
import '../context/context_manager.dart';
import '../context/event_store.dart';
import '../utils/format.dart';

/// Coordinates audio playback between host and slaves.
///
/// Extracted from SessionManager (CRIT-005 fix) to reduce God Object complexity.
///
/// Responsibilities:
/// - Host: play/pause/resume tracks, broadcast to slaves, file transfer
/// - Slave: receive and execute playback commands, clock-synced timing
/// - Both: playlist sync, seek, skip
class PlaybackCoordinator {
  final AudioEngine _audioEngine;
  final FileTransferService _fileTransfer;
  final ContextManager _contextManager;
  final Logger _logger;

  FirebaseService? _firebase;
  WebSocketServer? _server;
  WebSocketClient? _client;
  AudioSession? _session;
  DeviceRole _role = DeviceRole.none;

  /// Cached file path for slave playback.
  String? _cachedFilePath;

  PlaybackCoordinator({
    required AudioEngine audioEngine,
    required FileTransferService fileTransfer,
    required ContextManager contextManager,
    Logger? logger,
  })  : _audioEngine = audioEngine,
        _fileTransfer = fileTransfer,
        _contextManager = contextManager,
        _logger = logger ?? Logger();

  /// Set Firebase service for analytics (optional).
  void setFirebaseService(FirebaseService? service) => _firebase = service;

  /// Set the active server (host side).
  void setServer(WebSocketServer? server) => _server = server;

  /// Set the active client (slave side).
  void setClient(WebSocketClient? client) => _client = client;

  /// Set the current session.
  void setSession(AudioSession? session) => _session = session;

  /// Set the current device role.
  void setRole(DeviceRole role) => _role = role;

  /// Cached file path (set by file transfer completion).
  String? get cachedFilePath => _cachedFilePath;
  set cachedFilePath(String? path) => _cachedFilePath = path;

  // C10 fix: Mutex to prevent concurrent audio engine operations
  bool _isAudioEngineBusy = false;

  // MED-9 fix: Prevent concurrent playTrack calls
  bool _isPlaying = false;

  // ── Host Playback API ──

  /// Start playing a track (host only).
  Future<void> playTrack(
    AudioTrack track, {
    int delayMs = AppConstants.defaultPlayDelayMs,
    Playlist? playlist,
  }) async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can start playback');
    }
    // MED-9 fix: prevent concurrent playTrack calls
    if (_isPlaying) {
      _logger.w('playTrack already in progress, ignoring');
      return;
    }
    _isPlaying = true;
    try {
      // C8 fix: capture server reference before async operations
      final server = _server;
      if (server == null) {
        throw Exception('Server not initialized');
      }

      _logger.i('=== HOST PLAY TRACK ===');
      _logger.i('track: ${track.title}');
      _logger.i('source: ${track.source}');
      _logger.i('sourceType: ${track.sourceType}');

      // If it's a local file and we have slaves, send the file first
      String trackSource = track.source;

      if (track.sourceType == AudioSourceType.localFile && server.slaveCount > 0) {
        _logger.i('=== SENDING FILE TO SLAVES ===');
        _logger.i('Slaves count: ${server.slaveCount}');

        final sent = await _fileTransfer.sendFile(
          filePath: track.source,
          server: server,
        );

        if (sent) {
          _logger.i('File sent successfully to all slaves');
          trackSource = extractFileName(track.source);
          _logger.i('Broadcasting filename: $trackSource');
          await Future.delayed(
            const Duration(milliseconds: AppConstants.fileTransferWaitDelayMs),
          );
        } else {
          // H8 fix: log warning but continue — slaves will silently skip
          _logger.w('Failed to send file, slaves may not be able to play');
        }
      }

      // Load track locally
      _logger.d('Loading track locally on host...');
      await _audioEngine.loadTrack(track);

      // Send prepare command to slaves for pre-loading
      if (server.slaveCount > 0) {
        _logger.i('=== BROADCASTING PREPARE COMMAND ===');
        await server.broadcastPrepare(
          trackSource: trackSource,
          sourceType: track.sourceType,
        );
        await Future.delayed(
          const Duration(milliseconds: AppConstants.prepareBroadcastDelayMs),
        );
      }

      // Broadcast to slaves
      _logger.i('=== BROADCASTING PLAY COMMAND ===');
      await server.broadcastPlay(
        trackSource: trackSource,
        sourceType: track.sourceType,
        delayMs: delayMs,
      );

      // Play locally
      await Future.delayed(Duration(milliseconds: delayMs));
      await _audioEngine.play();

      _session = _session?.copyWith(
        state: SessionState.playing,
        currentTrack: track,
        startedAt: DateTime.now(),
      );

      await _contextManager.recordEvent(SessionEvent(
        sessionId: _session?.sessionId ?? '',
        type: EventType.playbackStarted,
        data: {'track': track.toJson()},
        timestamp: DateTime.now(),
      ));

      _firebase?.logTrackPlay(
        trackTitle: track.title,
        sourceType: track.sourceType.name,
      );

      // Broadcast playlist update to slaves
      if (server.slaveCount > 0 && playlist != null) {
        await server.broadcastPlaylistUpdate(
          tracks: playlist.tracks.map((t) => {
            'title': t.title,
            'artist': t.artist,
            'source': t.source,
            'sourceType': t.sourceType.name,
          }).toList(),
          currentIndex: playlist.currentIndex,
        );
      }
    } finally {
      _isPlaying = false;
    }
  }

  /// Pause playback (host only).
  Future<void> pausePlayback() async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can control playback');
    }
    if (_server == null) {
      throw Exception('Server not initialized');
    }

    final positionMs = _audioEngine.position.inMilliseconds;

    await _audioEngine.pause();
    await _server!.broadcastPause(positionMs: positionMs);

    _session = _session?.copyWith(state: SessionState.paused);

    await _contextManager.recordEvent(SessionEvent(
      sessionId: _session?.sessionId ?? '',
      type: EventType.playbackPaused,
      data: {'position_ms': positionMs},
      timestamp: DateTime.now(),
    ));
  }

  /// Resume playback (host only).
  Future<void> resumePlayback({
    int delayMs = AppConstants.resumeDelayMs,
  }) async {
    if (_role != DeviceRole.host) {
      throw Exception('Only the host can control playback');
    }
    // C8 fix: capture server reference before async operations
    final server = _server;
    if (server == null) {
      throw Exception('Server not initialized');
    }

    AudioTrack? track = _session?.currentTrack;
    track ??= _audioEngine.currentTrack;
    if (track == null) {
      _logger.w('resumePlayback: no track to resume');
      return;
    }

    final positionMs = _audioEngine.position.inMilliseconds;

    String trackSource = track.source;
    if (track.sourceType == AudioSourceType.localFile) {
      trackSource = extractFileName(track.source);
    }

    await server.broadcastPlay(
      trackSource: trackSource,
      sourceType: track.sourceType,
      delayMs: delayMs,
      seekPositionMs: positionMs,
    );

    await Future.delayed(Duration(milliseconds: delayMs));
    await _audioEngine.play();

    _session = _session?.copyWith(
      state: SessionState.playing,
      currentTrack: track,
    );

    await _contextManager.recordEvent(SessionEvent(
      sessionId: _session?.sessionId ?? '',
      type: EventType.playbackResumed,
      timestamp: DateTime.now(),
    ));
  }

  /// Broadcast playlist update to slaves (shuffle/repeat changes).
  void broadcastPlaylistUpdate({
    required List<Map<String, dynamic>> tracks,
    required int currentIndex,
    String? repeatMode,
    bool? isShuffled,
  }) {
    if (_role != DeviceRole.host || _server == null || _server!.slaveCount == 0) {
      return;
    }
    _server!.broadcastPlaylistUpdate(
      tracks: tracks,
      currentIndex: currentIndex,
      repeatMode: repeatMode,
      isShuffled: isShuffled,
    );
  }

  /// Sync a track to slaves without playing it (host only).
  Future<void> syncTrackToSlaves(AudioTrack track) async {
    if (_role != DeviceRole.host) return;
    if (_server == null || _server!.slaveCount == 0) return;
    if (track.sourceType != AudioSourceType.localFile) return;

    _logger.i('Syncing track to slaves: ${track.title}');

    String trackSource = track.source;
    final sent = await _fileTransfer.sendFile(
      filePath: track.source,
      server: _server!,
    );

    if (sent) {
      trackSource = extractFileName(track.source);
      _logger.i('File sent, broadcasting prepare for: $trackSource');
      await Future.delayed(
        const Duration(milliseconds: AppConstants.fileTransferWaitDelayMs),
      );
      await _server!.broadcastPrepare(
        trackSource: trackSource,
        sourceType: track.sourceType,
      );
    } else {
      _logger.w('Failed to sync track to slaves');
    }
  }

  // ── Slave Command Handlers ──

  /// Handle a prepare command received from the host.
  Future<void> handlePrepareCommand(ClientEvent event) async {
    if (event.trackSource == null) {
      _logger.w('Received prepare command with null trackSource, skipping');
      return;
    }

    _logger.i('=== PREPARE COMMAND RECEIVED ===');
    _logger.i('trackSource: ${event.trackSource}');
    _logger.i('sourceType: ${event.sourceType}');

    String trackSource = event.trackSource!;

    if (event.sourceType == AudioSourceType.localFile) {
      final cachePath = _fileTransfer.cachePath;
      if (cachePath == null) {
        _logger.w('No cache path available for prepare');
        return;
      }
      final cachedPath = '$cachePath/$trackSource';
      final cachedFile = File(cachedPath);

      bool found = false;
      for (int i = 0; i < 5; i++) {
        if (await cachedFile.exists()) {
          trackSource = cachedPath;
          _logger.d('File found in cache: $trackSource');
          found = true;
          break;
        }
        if (i < 4) {
          _logger.d('File not in cache yet, retrying... (${i + 1}/5)');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (!found) {
        _logger.w('File not in cache after retries, will check on play');
        return;
      }
    }

    final track = event.sourceType == AudioSourceType.localFile
        ? await AudioTrack.fromFilePathWithMetadata(trackSource)
        : AudioTrack.fromUrl(trackSource);

    await _audioEngine.preloadTrack(track);
    _logger.i('Track preloaded: ${track.title}');
  }

  /// Handle a play command received from the host (CRIT-006 fix: extracted from SessionManager).
  Future<void> handlePlayCommand(ClientEvent event) async {
    if (event.trackSource == null) {
      _logger.w('Received play command with null trackSource, skipping');
      return;
    }

    _logger.i('=== RECEIVED PLAY COMMAND ===');
    _logger.i('trackSource: ${event.trackSource}');
    _logger.i('sourceType: ${event.sourceType}');
    _logger.i('seekPositionMs: ${event.seekPositionMs}');
    _logger.i('startAtMs: ${event.startAtMs}');

    String trackSource = event.trackSource!;

    if (event.sourceType == AudioSourceType.localFile) {
      _logger.d('Looking for cached file...');
      String? cachedPath;

      if (_cachedFilePath != null) {
        final file = File(_cachedFilePath!);
        if (await file.exists()) {
          cachedPath = _cachedFilePath;
          _logger.d('Using cached path from memory: $cachedPath');
        }
      }

      if (cachedPath == null) {
        final cachePath = _fileTransfer.cachePath;
        if (cachePath != null) {
          final cachedFile = '$cachePath/${event.trackSource!}';
          final file = File(cachedFile);
          _logger.d('Checking cache file: $cachedFile');

          for (int i = 0; i < AppConstants.fileWaitRetryCount; i++) {
            if (await file.exists()) {
              cachedPath = cachedFile;
              _logger.d('Found cached file after ${i + 1} attempt(s)');
              break;
            }
            _logger.d(
              'Waiting for file... attempt ${i + 1}/${AppConstants.fileWaitRetryCount}',
            );
            await Future.delayed(
              const Duration(milliseconds: AppConstants.fileWaitRetryDelayMs),
            );
          }
        } else {
          _logger.e('No cache path available!');
        }
      }

      if (cachedPath != null) {
        trackSource = cachedPath;
        _logger.i('Using cached file: $trackSource');
      } else {
        _logger.e('!!! FILE NOT FOUND !!!');
        _logger.e('Event trackSource was: ${event.trackSource}');
        _logger.e('Cache path: ${_fileTransfer.cachePath}');
        _logger.e('Cached file path from memory: $_cachedFilePath');
        final cacheDir = _fileTransfer.cachePath != null
            ? Directory(_fileTransfer.cachePath!)
            : null;
        if (cacheDir != null && await cacheDir.exists()) {
          final files = await cacheDir.list().toList();
          _logger.e(
            'Files in cache dir: ${files.map((f) => f.path).join(', ')}',
          );
        } else {
          _logger.e('Cache directory does not exist');
        }
        _logger.w('File not received yet, skipping playback');
        return;
      }
    } else {
      _logger.d('Source is URL, no file transfer needed');
    }

    final track = event.sourceType == AudioSourceType.localFile
        ? await AudioTrack.fromFilePathWithMetadata(trackSource)
        : AudioTrack.fromUrl(trackSource);

    _logger.i('Creating AudioTrack: ${track.title}');

    try {
      _logger.d('Calling audioEngine.loadPreloaded...');
      _isAudioEngineBusy = true; // C10 fix: mark engine as busy
      await _audioEngine.loadPreloaded(track);
      _logger.i('AudioTrack loaded successfully');
    } catch (e, stack) {
      _logger.e('!!! FAILED TO LOAD TRACK !!!: $e');
      _firebase?.recordError(e, stack, reason: 'loadPreloaded');
      return;
    } finally {
      _isAudioEngineBusy = false;
    }

    if (event.seekPositionMs != null && event.seekPositionMs! > 0) {
      _logger.d('Seeking to position: ${event.seekPositionMs}ms');
      await _audioEngine.seek(
        Duration(milliseconds: event.seekPositionMs!),
      );
    }

    // Play at scheduled time
    int delayMs = 0;
    if (event.startAtMs != null) {
      if (_client != null && _client!.isConnected) {
        try {
          await _client!.synchronize();
          _logger.d(
            'Pre-play sync completed, offset: ${_client!.clockSync.stats.offsetMs}ms',
          );
        } catch (e) {
          _logger.w('Pre-play sync failed, using existing offset: $e');
        }
      }

      final clockOffsetMs = _client?.clockSync.stats.offsetMs ?? 0;
      final localStartAtMs =
          event.startAtMs! - clockOffsetMs.round();
      delayMs = localStartAtMs - DateTime.now().millisecondsSinceEpoch;
      // HIGH-2 fix: sanity check for extreme clock skew
      if (delayMs < -AppConstants.lateCompensationMaxCompensationMs) {
        _logger.w('Extreme clock skew detected (${delayMs}ms), playing immediately');
        delayMs = 0;
      }
      _logger.d(
        'Clock offset: ${clockOffsetMs.toStringAsFixed(1)}ms, '
        'host startAt: ${event.startAtMs}, local startAt: $localStartAtMs, delay: ${delayMs}ms',
      );
    }

    if (delayMs > 0 && delayMs < AppConstants.lateCompensationThresholdMs) {
      _logger.i('Waiting ${delayMs}ms before playing...');
      await Future.delayed(Duration(milliseconds: delayMs));
    } else if (delayMs < 0) {
      final lateMs = -delayMs;
      _logger.w('Late by ${lateMs}ms, seeking forward to compensate');
      if (lateMs < AppConstants.lateCompensationMaxCompensationMs) {
        final currentPosition = _audioEngine.position.inMilliseconds;
        // CRIT-3 fix: clamp seek position to valid range [0, duration]
        final durationMs = _audioEngine.duration?.inMilliseconds ?? (currentPosition + lateMs);
        final seekPos = (currentPosition + lateMs).clamp(0, durationMs);
        await _audioEngine.seek(
          Duration(milliseconds: seekPos),
        );
        _logger.i(
          'Seeked to ${seekPos}ms to compensate for ${lateMs}ms delay',
        );
      } else {
        _logger.e(
          'Too late (${lateMs}ms > ${AppConstants.lateCompensationMaxCompensationMs}ms), playing from current position',
        );
      }
    } else if (delayMs >= AppConstants.lateCompensationThresholdMs) {
      _logger.w(
        'Delay too large (${delayMs}ms), capping to ${AppConstants.lateCompensationThresholdMs}ms',
      );
      await Future.delayed(
        const Duration(milliseconds: AppConstants.lateCompensationThresholdMs),
      );
    }

    _logger.d('Calling audioEngine.play()...');
    await _audioEngine.play();
    _logger.i('=== PLAYBACK STARTED ON SLAVE ===');
  }

  /// Handle a pause command received from the host.
  Future<void> handlePauseCommand(ClientEvent event) async {
    // HIGH-5 fix: wrap in try-catch
    try {
      await _audioEngine.pause();
    } catch (e) {
      _logger.e('Failed to pause: $e');
    }
  }

  /// Handle a seek command received from the host.
  Future<void> handleSeekCommand(ClientEvent event) async {
    // HIGH-6 fix: wrap in try-catch
    if (event.positionMs != null) {
      try {
        await _audioEngine.seek(
          Duration(milliseconds: event.positionMs!),
        );
      } catch (e) {
        _logger.e('Failed to seek: $e');
      }
    }
  }

  /// Handle a playlist update command received from the host.
  void handlePlaylistUpdateCommand(
    ClientEvent event,
    StreamController<PlaylistUpdate> playlistUpdateController,
  ) {
    if (event.playlistTracks == null) return;
    _logger.i(
      'Received playlist update: ${event.playlistTracks!.length} tracks',
    );
    if (!playlistUpdateController.isClosed) {
      playlistUpdateController.add(PlaylistUpdate(
        tracks: event.playlistTracks!,
        currentIndex: event.playlistCurrentIndex ?? 0,
      ));
    }
  }

  // ── File Transfer Handlers (slave side) ──

  /// Handle file transfer JSON messages (slave side).
  Future<void> handleFileTransferMessage(
    ClientEvent event,
  ) async {
    if (event.protocolMessage == null) {
      _logger.w('Received file transfer message with null protocolMessage');
      return;
    }

    _logger.i('=== PROCESSING FILE TRANSFER MESSAGE ===');
    _logger.i('Message type: ${event.protocolMessage!.type}');

    final result = await _fileTransfer.handleIncomingMessage(
      event.protocolMessage!,
    );

    if (result != null) {
      _cachedFilePath = result;
      _logger.i('=== FILE TRANSFER COMPLETE ===');
      _logger.i('File saved at: $result');

      if (_client != null) {
        final ack = ProtocolMessage.fileTransferAck();
        _client!.sendMessage(ack);
        _logger.d('Sent file transfer ACK to host');
      }

      await _autoPreloadTrack(result);
    } else {
      _logger.d('File transfer in progress or not complete yet');
    }
  }

  /// Handle file transfer binary chunks (slave side).
  Future<void> handleFileTransferBinary(ClientEvent event) async {
    if (event.binaryData == null) {
      _logger.w('Received file transfer binary with null data');
      return;
    }

    _logger.d('=== PROCESSING BINARY FILE TRANSFER CHUNK ===');

    final result = await _fileTransfer.handleBinaryChunk(event.binaryData!);

    if (result != null) {
      _cachedFilePath = result;
      _logger.i('=== FILE TRANSFER COMPLETE (binary) ===');
      _logger.i('File saved at: $result');

      if (_client != null) {
        final ack = ProtocolMessage.fileTransferAck();
        _client!.sendMessage(ack);
        _logger.d('Sent file transfer ACK to host');
      }

      await _autoPreloadTrack(result);
    }
  }

  /// Auto-preload a track after file transfer completion.
  Future<void> _autoPreloadTrack(String filePath) async {
    // C10 fix: skip if audio engine is busy (e.g., handlePlayCommand is loading)
    if (_isAudioEngineBusy) {
      _logger.d('Skipping auto-preload: audio engine busy');
      return;
    }
    try {
      _isAudioEngineBusy = true;
      final file = File(filePath);
      if (await file.exists()) {
        final track = await AudioTrack.fromFilePathWithMetadata(filePath);
        await _audioEngine.preloadTrack(track);
        _logger.i('Auto-preloaded track after file transfer: ${track.title}');
      }
    } catch (e) {
      _logger.w('Auto-preload after transfer failed (non-critical): $e');
    } finally {
      _isAudioEngineBusy = false;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _server = null;
    _client = null;
    _session = null;
    _cachedFilePath = null;
  }
}

/// Playlist update received from the host.
class PlaylistUpdate {
  final List<Map<String, dynamic>> tracks;
  final int currentIndex;

  const PlaylistUpdate({
    required this.tracks,
    required this.currentIndex,
  });
}
