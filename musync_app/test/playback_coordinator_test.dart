import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musync_mimo/core/core.dart';
import 'package:musync_mimo/core/session/playback_coordinator.dart';

// ── Mocks ──

class MockAudioEngine extends Mock implements AudioEngine {}

class MockFileTransferService extends Mock implements FileTransferService {}

class MockContextManager extends Mock implements ContextManager {}

class MockWebSocketServer extends Mock implements WebSocketServer {}

class MockWebSocketClient extends Mock implements WebSocketClient {}

class MockClockSyncEngine extends Mock implements ClockSyncEngine {}

class MockFirebaseService extends Mock implements FirebaseService {}

// ── Fakes ──

class FakeAudioTrack extends Fake implements AudioTrack {}

class FakeProtocolMessage extends Fake implements ProtocolMessage {}

class FakeClientEvent extends Fake implements ClientEvent {}

class FakeWebSocketServer extends Fake implements WebSocketServer {}

class FakeSessionEvent extends Fake implements SessionEvent {}

void main() {
  late PlaybackCoordinator coordinator;
  late MockAudioEngine audioEngine;
  late MockFileTransferService fileTransfer;
  late MockContextManager contextManager;
  late MockWebSocketServer server;
  late MockWebSocketClient client;
  late MockClockSyncEngine clockSync;
  late MockFirebaseService firebase;

  setUpAll(() {
    registerFallbackValue(FakeAudioTrack());
    registerFallbackValue(FakeProtocolMessage());
    registerFallbackValue(FakeClientEvent());
    registerFallbackValue(FakeWebSocketServer());
    registerFallbackValue(FakeSessionEvent());
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    audioEngine = MockAudioEngine();
    fileTransfer = MockFileTransferService();
    contextManager = MockContextManager();
    server = MockWebSocketServer();
    client = MockWebSocketClient();
    clockSync = MockClockSyncEngine();
    firebase = MockFirebaseService();

    coordinator = PlaybackCoordinator(
      audioEngine: audioEngine,
      fileTransfer: fileTransfer,
      contextManager: contextManager,
    );
    coordinator.setFirebaseService(firebase);

    // Audio engine stubs
    when(() => audioEngine.loadTrack(any())).thenAnswer((_) async {});
    when(() => audioEngine.preloadTrack(any())).thenAnswer((_) async {});
    when(() => audioEngine.loadPreloaded(any())).thenAnswer((_) async {});
    when(() => audioEngine.play()).thenAnswer((_) async {});
    when(() => audioEngine.pause()).thenAnswer((_) async {});
    when(() => audioEngine.seek(any())).thenAnswer((_) async {});
    when(() => audioEngine.position).thenReturn(Duration.zero);
    when(() => audioEngine.currentTrack).thenReturn(null);

    // File transfer stubs
    when(() => fileTransfer.sendFile(
          filePath: any(named: 'filePath'),
          server: any(named: 'server'),
        )).thenAnswer((_) async => true);
    when(() => fileTransfer.cachePath).thenReturn('/tmp/musync_cache');
    when(() => fileTransfer.handleIncomingMessage(any()))
        .thenAnswer((_) async => null);
    when(() => fileTransfer.handleBinaryChunk(any()))
        .thenAnswer((_) async => null);

    // Context manager stubs
    when(() => contextManager.recordEvent(any())).thenAnswer((_) async {});

    // Server stubs — use concrete enum values instead of matchers for AudioSourceType
    when(() => server.slaveCount).thenReturn(0);
    when(() => server.broadcast(any())).thenAnswer((_) async {});
    when(() => server.broadcastPrepare(
          trackSource: any(named: 'trackSource'),
          sourceType: AudioSourceType.url,
        )).thenAnswer((_) async {});
    when(() => server.broadcastPrepare(
          trackSource: any(named: 'trackSource'),
          sourceType: AudioSourceType.localFile,
        )).thenAnswer((_) async {});
    when(() => server.broadcastPlay(
          trackSource: any(named: 'trackSource'),
          sourceType: AudioSourceType.url,
          delayMs: any(named: 'delayMs'),
          seekPositionMs: any(named: 'seekPositionMs'),
        )).thenAnswer((_) async {});
    when(() => server.broadcastPlay(
          trackSource: any(named: 'trackSource'),
          sourceType: AudioSourceType.localFile,
          delayMs: any(named: 'delayMs'),
          seekPositionMs: any(named: 'seekPositionMs'),
        )).thenAnswer((_) async {});
    when(() => server.broadcastPause(
          positionMs: any(named: 'positionMs'),
        )).thenAnswer((_) async {});
    when(() => server.broadcastPlaylistUpdate(
          tracks: any(named: 'tracks'),
          currentIndex: any(named: 'currentIndex'),
          repeatMode: any(named: 'repeatMode'),
          isShuffled: any(named: 'isShuffled'),
        )).thenAnswer((_) async {});

    // Client stubs
    when(() => client.clockSync).thenReturn(clockSync);
    when(() => client.isConnected).thenReturn(true);
    when(() => client.sendMessage(any())).thenReturn(null);
    when(() => clockSync.stats).thenReturn(
      ClockSyncStats(
        offsetMs: 0,
        driftPpm: 0,
        jitterMs: 0,
        sampleCount: 8,
        lastCalibration: DateTime.now(),
        isCalibrated: true,
      ),
    );
    when(() => client.synchronize()).thenAnswer((_) async => true);

    // Firebase stubs
    when(() => firebase.logTrackPlay(
          trackTitle: any(named: 'trackTitle'),
          sourceType: any(named: 'sourceType'),
        )).thenAnswer((_) async {});
  });

  tearDown(() {
    resetMocktailState();
  });

  // ── Host Playback Tests ──

  group('PlaybackCoordinator - Host', () {
    setUp(() {
      coordinator.setRole(DeviceRole.host);
      coordinator.setServer(server);
    });

    test('playTrack throws if not host', () async {
      coordinator.setRole(DeviceRole.slave);
      final track = AudioTrack.fromUrl('http://example.com/song.mp3');
      expect(
        () => coordinator.playTrack(track),
        throwsA(isA<Exception>()),
      );
    });

    test('playTrack throws if server not set', () async {
      coordinator.setServer(null);
      final track = AudioTrack.fromUrl('http://example.com/song.mp3');
      expect(
        () => coordinator.playTrack(track),
        throwsA(isA<Exception>()),
      );
    });

    test('playTrack URL track broadcasts and plays', () async {
      when(() => server.slaveCount).thenReturn(2);
      final track = AudioTrack.fromUrl('http://example.com/song.mp3');

      await coordinator.playTrack(track, delayMs: 0);

      verify(() => server.broadcastPlay(
            trackSource: 'http://example.com/song.mp3',
            sourceType: AudioSourceType.url,
            delayMs: 0,
          )).called(1);
      verify(() => audioEngine.loadTrack(track)).called(1);
      verify(() => audioEngine.play()).called(1);
    });

    test('pausePlayback broadcasts pause', () async {
      when(() => server.slaveCount).thenReturn(1);
      when(() => audioEngine.position).thenReturn(const Duration(seconds: 30));

      await coordinator.pausePlayback();

      verify(() => audioEngine.pause()).called(1);
      verify(() => server.broadcastPause(positionMs: 30000)).called(1);
    });

    test('resumePlayback broadcasts play with seek position', () async {
      when(() => server.slaveCount).thenReturn(1);
      final track = AudioTrack.fromUrl('http://example.com/song.mp3');
      coordinator.setSession(AudioSession.create(
        host: DeviceInfo(
          id: 'host1',
          name: 'Host',
          type: DeviceType.phone,
          ip: '192.168.1.1',
          port: 7890,
          discoveredAt: DateTime.now(),
        ),
      ).copyWith(currentTrack: track));
      when(() => audioEngine.position).thenReturn(const Duration(seconds: 45));
      when(() => audioEngine.currentTrack).thenReturn(track);

      await coordinator.resumePlayback(delayMs: 0);

      verify(() => server.broadcastPlay(
            trackSource: any(named: 'trackSource'),
            sourceType: AudioSourceType.url,
            delayMs: 0,
            seekPositionMs: 45000,
          )).called(1);
      verify(() => audioEngine.play()).called(1);
    });

    test('syncTrackToSlaves sends file and broadcasts prepare', () async {
      when(() => server.slaveCount).thenReturn(2);
      final track = AudioTrack.fromFilePath('/tmp/song.mp3');

      await coordinator.syncTrackToSlaves(track);

      verify(() => fileTransfer.sendFile(
            filePath: '/tmp/song.mp3',
            server: server,
          )).called(1);
      verify(() => server.broadcastPrepare(
            trackSource: 'song.mp3',
            sourceType: AudioSourceType.localFile,
          )).called(1);
    });

    test('syncTrackToSlaves does nothing for URL tracks', () async {
      when(() => server.slaveCount).thenReturn(2);
      final track = AudioTrack.fromUrl('http://example.com/song.mp3');

      await coordinator.syncTrackToSlaves(track);

      verifyNever(() => fileTransfer.sendFile(
            filePath: any(named: 'filePath'),
            server: any(named: 'server'),
          ));
    });

    test('broadcastPlaylistUpdate forwards to server', () async {
      when(() => server.slaveCount).thenReturn(1);
      final tracks = [
        {'title': 'Song 1', 'artist': 'Artist', 'source': 's1', 'sourceType': 'url'},
      ];

      coordinator.broadcastPlaylistUpdate(
        tracks: tracks,
        currentIndex: 0,
      );

      verify(() => server.broadcastPlaylistUpdate(
            tracks: tracks,
            currentIndex: 0,
          )).called(1);
    });

    test('broadcastPlaylistUpdate does nothing when no slaves', () async {
      when(() => server.slaveCount).thenReturn(0);
      final tracks = [
        {'title': 'Song 1', 'artist': 'Artist', 'source': 's1', 'sourceType': 'url'},
      ];

      coordinator.broadcastPlaylistUpdate(
        tracks: tracks,
        currentIndex: 0,
      );

      verifyNever(() => server.broadcastPlaylistUpdate(
            tracks: any(named: 'tracks'),
            currentIndex: any(named: 'currentIndex'),
          ));
    });
  });

  // ── Slave Command Handler Tests ──

  group('PlaybackCoordinator - Slave Commands', () {
    setUp(() {
      coordinator.setRole(DeviceRole.slave);
      coordinator.setClient(client);
    });

    test('handlePrepareCommand skips if trackSource is null', () async {
      final event = ClientEvent(
        type: ClientEventType.prepareCommand,
        trackSource: null,
      );

      await coordinator.handlePrepareCommand(event);

      verifyNever(() => audioEngine.preloadTrack(any()));
    });

    test('handlePauseCommand pauses audio engine', () async {
      final event = ClientEvent(
        type: ClientEventType.pauseCommand,
        positionMs: 5000,
      );

      await coordinator.handlePauseCommand(event);

      verify(() => audioEngine.pause()).called(1);
    });

    test('handleSeekCommand seeks to position', () async {
      final event = ClientEvent(
        type: ClientEventType.seekCommand,
        positionMs: 30000,
      );

      await coordinator.handleSeekCommand(event);

      verify(() => audioEngine.seek(const Duration(milliseconds: 30000)))
          .called(1);
    });

    test('handleSeekCommand does nothing if positionMs is null', () async {
      final event = ClientEvent(
        type: ClientEventType.seekCommand,
        positionMs: null,
      );

      await coordinator.handleSeekCommand(event);

      verifyNever(() => audioEngine.seek(any()));
    });

    test('handlePlaylistUpdateCommand emits to controller', () async {
      final event = ClientEvent(
        type: ClientEventType.playlistUpdateCommand,
        playlistTracks: [
          {'title': 'Song 1', 'source': 's1', 'sourceType': 'url'},
        ],
        playlistCurrentIndex: 0,
      );

      final controller = StreamController<PlaylistUpdate>.broadcast();
      final emitted = <PlaylistUpdate>[];
      final sub = controller.stream.listen(emitted.add);

      coordinator.handlePlaylistUpdateCommand(event, controller);

      // Give the event loop a chance to deliver the event
      await Future.delayed(const Duration(milliseconds: 10));

      expect(emitted.length, 1);
      expect(emitted.first.tracks.length, 1);
      expect(emitted.first.currentIndex, 0);

      await sub.cancel();
      await controller.close();
    });

    test('handlePlaylistUpdateCommand ignores null tracks', () async {
      final event = ClientEvent(
        type: ClientEventType.playlistUpdateCommand,
        playlistTracks: null,
      );

      final controller = StreamController<PlaylistUpdate>.broadcast();
      coordinator.handlePlaylistUpdateCommand(event, controller);

      expect(controller.stream, neverEmits(isA<PlaylistUpdate>()));
      await controller.close();
    });
  });

  // ── File Transfer Handler Tests ──

  group('PlaybackCoordinator - File Transfer', () {
    setUp(() {
      coordinator.setRole(DeviceRole.slave);
      coordinator.setClient(client);
    });

    test('handleFileTransferMessage skips if protocolMessage is null', () async {
      final event = ClientEvent(
        type: ClientEventType.fileTransferMessage,
        protocolMessage: null,
      );

      await coordinator.handleFileTransferMessage(event);

      verifyNever(() => fileTransfer.handleIncomingMessage(any()));
    });

    test('handleFileTransferMessage delegates to fileTransfer', () async {
      final msg = ProtocolMessage.fileTransferStart(
        fileName: 'song.mp3',
        fileSizeBytes: 1000,
        totalChunks: 1,
        chunkSizeBytes: 1000,
      );
      final event = ClientEvent(
        type: ClientEventType.fileTransferMessage,
        protocolMessage: msg,
      );

      await coordinator.handleFileTransferMessage(event);

      verify(() => fileTransfer.handleIncomingMessage(msg)).called(1);
    });

    test('handleFileTransferBinary skips if binaryData is null', () async {
      final event = ClientEvent(
        type: ClientEventType.fileTransferBinary,
        binaryData: null,
      );

      await coordinator.handleFileTransferBinary(event);

      verifyNever(() => fileTransfer.handleBinaryChunk(any()));
    });

    test('handleFileTransferBinary delegates to fileTransfer', () async {
      final event = ClientEvent(
        type: ClientEventType.fileTransferBinary,
        binaryData: [1, 2, 3],
      );

      await coordinator.handleFileTransferBinary(event);

      verify(() => fileTransfer.handleBinaryChunk([1, 2, 3])).called(1);
    });
  });

  // ── State Management Tests ──

  group('PlaybackCoordinator - State', () {
    test('cachedFilePath getter/setter works', () {
      expect(coordinator.cachedFilePath, isNull);
      coordinator.cachedFilePath = '/tmp/song.mp3';
      expect(coordinator.cachedFilePath, '/tmp/song.mp3');
    });

    test('dispose clears all references', () async {
      coordinator.setServer(server);
      coordinator.setClient(client);
      coordinator.setSession(AudioSession.create(
        host: DeviceInfo(
          id: 'h1',
          name: 'H',
          type: DeviceType.phone,
          ip: '',
          port: 0,
          discoveredAt: DateTime.now(),
        ),
      ));
      coordinator.setRole(DeviceRole.host);
      coordinator.cachedFilePath = '/tmp/song.mp3';

      await coordinator.dispose();

      expect(coordinator.cachedFilePath, isNull);
    });
  });

  // ── PlaylistUpdate Model Tests ──

  group('PlaylistUpdate', () {
    test('creates with required fields', () {
      final update = PlaylistUpdate(
        tracks: [
          {'title': 'Song 1', 'source': 's1', 'sourceType': 'url'},
        ],
        currentIndex: 0,
      );

      expect(update.tracks.length, 1);
      expect(update.currentIndex, 0);
    });
  });
}
