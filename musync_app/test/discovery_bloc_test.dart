import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musync_mimo/core/core.dart';
import 'package:musync_mimo/features/discovery/bloc/discovery_bloc.dart';

// ── Mocks ──

class MockSessionManager extends Mock implements SessionManager {}

class MockAudioEngine extends Mock implements AudioEngine {}

class MockFileTransferService extends Mock implements FileTransferService {}

// ── Fakes ──

class FakeDeviceInfo extends Fake implements DeviceInfo {}

void main() {
  late MockSessionManager sessionManager;
  late MockAudioEngine audioEngine;
  late MockFileTransferService fileTransfer;

  // Helper: create a test device
  DeviceInfo makeDevice({
    String id = 'device-1',
    String name = 'Test Device',
    String ip = '192.168.1.100',
    int port = 7890,
    DeviceType type = DeviceType.phone,
    DeviceRole role = DeviceRole.none,
  }) {
    return DeviceInfo(
      id: id,
      name: name,
      type: type,
      ip: ip,
      port: port,
      role: role,
      discoveredAt: DateTime.now(),
    );
  }

  setUpAll(() {
    registerFallbackValue(FakeDeviceInfo());
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    sessionManager = MockSessionManager();
    audioEngine = MockAudioEngine();
    fileTransfer = MockFileTransferService();

    // Stub sessionManager getters
    when(() => sessionManager.audioEngine).thenReturn(audioEngine);
    when(() => sessionManager.fileTransfer).thenReturn(fileTransfer);
    when(() => sessionManager.role).thenReturn(DeviceRole.none);
    when(() => sessionManager.currentSession).thenReturn(null);

    // Stub streams with empty streams (no events)
    when(() => sessionManager.devicesStream).thenAnswer(
      (_) => Stream<List<DeviceInfo>>.fromIterable([]),
    );
    when(() => sessionManager.stateStream).thenAnswer(
      (_) => Stream<SessionManagerState>.fromIterable([]),
    );
    when(() => sessionManager.playlistUpdateStream).thenAnswer(
      (_) => Stream<PlaylistUpdate>.fromIterable([]),
    );
    when(() => sessionManager.syncQualityStream).thenAnswer(
      (_) => Stream<SyncQualityUpdate>.fromIterable([]),
    );
    when(() => sessionManager.apkTransferOfferStream).thenAnswer(
      (_) => Stream<ApkTransferOffer>.fromIterable([]),
    );

    // Stub audio engine streams
    when(() => audioEngine.stateStream).thenAnswer(
      (_) => Stream<AudioEngineState>.fromIterable([]),
    );
    when(() => audioEngine.positionStream).thenAnswer(
      (_) => Stream<Duration>.fromIterable([]),
    );
    when(() => audioEngine.position).thenReturn(Duration.zero);
    when(() => audioEngine.duration).thenReturn(const Duration(minutes: 3));
    when(() => audioEngine.currentTrack).thenReturn(null);

    // Stub file transfer stream
    when(() => fileTransfer.progressStream).thenAnswer(
      (_) => Stream<TransferProgress>.fromIterable([]),
    );
  });

  // ── Initial State ──

  group('DiscoveryBloc - Initial State', () {
    test('initial state is correct', () {
      final bloc = DiscoveryBloc(sessionManager: sessionManager);
      expect(bloc.state.status, DiscoveryStatus.idle);
      expect(bloc.state.availableDevices, isEmpty);
      expect(bloc.state.currentSessionId, isNull);
      expect(bloc.state.role, DeviceRole.none);
      expect(bloc.state.errorMessage, isNull);
      expect(bloc.state.connectedDeviceCount, 0);
      expect(bloc.state.currentTrack, isNull);
      expect(bloc.state.isPlaying, false);
      expect(bloc.state.position, Duration.zero);
      expect(bloc.state.syncQuality, SyncQuality.unknown);
      expect(bloc.state.syncOffsetMs, 0);
      expect(bloc.state.fileTransferProgress, isNull);
      expect(bloc.state.connectionDetail, ConnectionDetail.idle);
      expect(bloc.state.playlistTracks, isEmpty);
      expect(bloc.state.playlistCurrentIndex, 0);
      bloc.close();
    });
  });

  // ── Scanning ──

  group('DiscoveryBloc - Scanning', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'StartScanning emits scanning status',
      build: () {
        when(() => sessionManager.startScanning()).thenAnswer((_) async {});
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const StartScanning()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.scanning)
            .having((s) => s.errorMessage, 'errorMessage', isNull),
      ],
      verify: (_) {
        verify(() => sessionManager.startScanning()).called(1);
      },
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'StartScanning emits error on failure',
      build: () {
        when(() => sessionManager.startScanning())
            .thenThrow(Exception('Network error'));
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const StartScanning()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.scanning),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', contains('Network error')),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'StopScanning emits idle status',
      build: () {
        when(() => sessionManager.stopScanning()).thenAnswer((_) async {});
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const StopScanning()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.idle),
      ],
      verify: (_) {
        verify(() => sessionManager.stopScanning()).called(1);
      },
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'StopScanning emits error on failure',
      build: () {
        when(() => sessionManager.stopScanning())
            .thenThrow(Exception('Stop failed'));
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const StopScanning()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', contains('Stop failed')),
      ],
    );
  });

  // ── Device Management ──

  group('DiscoveryBloc - Device Management', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'DeviceFound adds device to list',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1'))),
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          1,
        ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'DeviceFound updates existing device',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1')));
        bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1 Updated')));
      },
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.first.name,
          'name',
          'Phone 1',
        ),
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.first.name,
          'name',
          'Phone 1 Updated',
        ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'DeviceFound adds multiple different devices',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1')));
        bloc.add(DeviceFound(makeDevice(id: 'dev-2', name: 'Phone 2')));
        bloc.add(DeviceFound(makeDevice(id: 'dev-3', name: 'Phone 3')));
      },
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          1,
        ),
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          2,
        ),
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          3,
        ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'DeviceLost removes device from list',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1')));
        bloc.add(DeviceFound(makeDevice(id: 'dev-2', name: 'Phone 2')));
        bloc.add(const DeviceLost('dev-1'));
      },
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          1,
        ),
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          2,
        ),
        isA<DiscoveryState>()
            .having((s) => s.availableDevices.length, 'devices', 1)
            .having(
              (s) => s.availableDevices.first.id,
              'remaining id',
              'dev-2',
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'DeviceLost does nothing if device not found',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(DeviceFound(makeDevice(id: 'dev-1', name: 'Phone 1')));
        bloc.add(const DeviceLost('non-existent'));
      },
      expect: () => [
        // Only one state emitted: DeviceFound adds the device
        // DeviceLost doesn't change anything (device not found), so no new emission
        isA<DiscoveryState>().having(
          (s) => s.availableDevices.length,
          'devices',
          1,
        ),
      ],
    );
  });

  // ── Host Session ──

  group('DiscoveryBloc - Host Session', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'HostSessionRequested creates session',
      build: () {
        when(() => sessionManager.hostSession())
            .thenAnswer((_) async => 'session-abc');
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const HostSessionRequested()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.hosting)
            .having((s) => s.errorMessage, 'errorMessage', isNull),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.hosting)
            .having((s) => s.currentSessionId, 'sessionId', 'session-abc')
            .having((s) => s.role, 'role', DeviceRole.host),
      ],
      verify: (_) {
        verify(() => sessionManager.hostSession()).called(1);
      },
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'HostSessionRequested emits error on failure',
      build: () {
        when(() => sessionManager.hostSession())
            .thenThrow(Exception('Port busy'));
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const HostSessionRequested()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.hosting),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', contains('Port busy')),
      ],
    );
  });

  // ── Join Session ──

  group('DiscoveryBloc - Join Session', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'JoinSessionRequested connects to host',
      build: () {
        when(() => sessionManager.joinSession(
              hostIp: any(named: 'hostIp'),
              hostPort: any(named: 'hostPort'),
            )).thenAnswer((_) async => true);
        when(() => sessionManager.stopScanning()).thenAnswer((_) async {});
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(JoinSessionRequested(
        makeDevice(id: 'host-1', name: 'Host', ip: '192.168.1.50'),
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joining)
            .having((s) => s.hostDevice?.id, 'hostDevice', 'host-1')
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connecting,
            ),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joined)
            .having((s) => s.role, 'role', DeviceRole.slave)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'JoinSessionRequested emits error when connection fails',
      build: () {
        when(() => sessionManager.joinSession(
              hostIp: any(named: 'hostIp'),
              hostPort: any(named: 'hostPort'),
            )).thenAnswer((_) async => false);
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(JoinSessionRequested(
        makeDevice(id: 'host-1', name: 'Host', ip: '192.168.1.50'),
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joining),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.error,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'JoinSessionRequested emits error on exception',
      build: () {
        when(() => sessionManager.joinSession(
              hostIp: any(named: 'hostIp'),
              hostPort: any(named: 'hostPort'),
            )).thenThrow(Exception('Timeout'));
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(JoinSessionRequested(
        makeDevice(id: 'host-1', name: 'Host', ip: '192.168.1.50'),
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joining),
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', contains('Timeout'))
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.error,
            ),
      ],
    );
  });

  // ── Session Lifecycle ──

  group('DiscoveryBloc - Session Lifecycle', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionCreated sets session ID and host role',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const SessionCreated('sess-123')),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.hosting)
            .having((s) => s.currentSessionId, 'sessionId', 'sess-123')
            .having((s) => s.role, 'role', DeviceRole.host),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionJoined sets slave role and connected detail',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const SessionJoined()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joined)
            .having((s) => s.role, 'role', DeviceRole.slave)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'LeaveSessionRequested resets to initial state',
      build: () {
        when(() => sessionManager.leaveSession()).thenAnswer((_) async {});
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const LeaveSessionRequested()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.idle)
            .having((s) => s.role, 'role', DeviceRole.none)
            .having((s) => s.currentSessionId, 'sessionId', isNull),
      ],
      verify: (_) {
        verify(() => sessionManager.leaveSession()).called(1);
      },
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'LeaveSessionRequested emits error on failure',
      build: () {
        when(() => sessionManager.leaveSession())
            .thenThrow(Exception('Disconnect failed'));
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(const LeaveSessionRequested()),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('Disconnect failed'),
            ),
      ],
    );
  });

  // ── Session State Changes ──

  group('DiscoveryBloc - Session State Changes', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged idle resets state',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.idle),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.idle)
            .having((s) => s.role, 'role', DeviceRole.none),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged hosting sets host role',
      build: () {
        when(() => sessionManager.currentSession).thenReturn(null);
        return DiscoveryBloc(sessionManager: sessionManager);
      },
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.hosting),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.hosting)
            .having((s) => s.role, 'role', DeviceRole.host)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged joined sets slave role',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.joined),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.joined)
            .having((s) => s.role, 'role', DeviceRole.slave)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged playing sets isPlaying true',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.playing),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.isPlaying, 'isPlaying', true)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged paused sets isPlaying false',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.paused),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.isPlaying, 'isPlaying', false)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SessionStateChanged error sets error status',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(
        const SessionStateChanged(SessionManagerState.error),
      ),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.status, 'status', DiscoveryStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', 'Session error')
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.error,
            ),
      ],
    );
  });

  // ── Playback State ──

  group('DiscoveryBloc - Playback State', () {
    final testTrack = AudioTrack(
      id: 'track-1',
      title: 'Test Song',
      source: '/path/to/song.mp3',
      sourceType: AudioSourceType.localFile,
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'PlaybackStateChanged updates track and position',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(PlaybackStateChanged(
        track: testTrack,
        isPlaying: true,
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 3),
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.currentTrack?.title, 'track', 'Test Song')
            .having((s) => s.isPlaying, 'isPlaying', true)
            .having(
              (s) => s.position,
              'position',
              const Duration(seconds: 30),
            )
            .having(
              (s) => s.duration,
              'duration',
              const Duration(minutes: 3),
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'PlaybackStateChanged with null track clears track',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(PlaybackStateChanged(
          track: testTrack,
          isPlaying: true,
          position: Duration.zero,
        ));
        bloc.add(const PlaybackStateChanged(
          track: null,
          isPlaying: false,
          position: Duration.zero,
        ));
      },
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.currentTrack?.title,
          'track',
          'Test Song',
        ),
        isA<DiscoveryState>()
            .having((s) => s.currentTrack, 'track', isNull)
            .having((s) => s.isPlaying, 'isPlaying', false),
      ],
    );
  });

  // ── Sync Quality ──

  group('DiscoveryBloc - Sync Quality', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'SyncQualityChanged updates quality and offset',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const SyncQualityChanged(
        quality: SyncQuality.excellent,
        offsetMs: 5.0,
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having(
              (s) => s.syncQuality,
              'quality',
              SyncQuality.excellent,
            )
            .having((s) => s.syncOffsetMs, 'offset', 5.0),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'SyncQualityChanged degraded quality',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const SyncQualityChanged(
        quality: SyncQuality.degraded,
        offsetMs: 150.0,
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having(
              (s) => s.syncQuality,
              'quality',
              SyncQuality.degraded,
            )
            .having((s) => s.syncOffsetMs, 'offset', 150.0),
      ],
    );
  });

  // ── File Transfer ──

  group('DiscoveryBloc - File Transfer', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'FileTransferProgressChanged updates progress',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const FileTransferProgressChanged(0.5)),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.fileTransferProgress, 'progress', 0.5)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.fileTransferring,
            ),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'FileTransferProgressChanged 100% sets connected',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const FileTransferProgressChanged(1.0)),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.fileTransferProgress, 'progress', 1.0)
            .having(
              (s) => s.connectionDetail,
              'connectionDetail',
              ConnectionDetail.connected,
            ),
      ],
    );
  });

  // ── Playlist ──

  group('DiscoveryBloc - Playlist', () {
    blocTest<DiscoveryBloc, DiscoveryState>(
      'PlaylistUpdated updates tracks and index',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) => bloc.add(const PlaylistUpdated(
        tracks: [
          {'title': 'Song 1', 'source': '/path/1.mp3'},
          {'title': 'Song 2', 'source': '/path/2.mp3'},
        ],
        currentIndex: 1,
      )),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.playlistTracks.length, 'tracks', 2)
            .having((s) => s.playlistTracks.first['title'], 'first title', 'Song 1')
            .having((s) => s.playlistCurrentIndex, 'index', 1),
      ],
    );

    blocTest<DiscoveryBloc, DiscoveryState>(
      'PlaylistUpdated empty list clears playlist',
      build: () => DiscoveryBloc(sessionManager: sessionManager),
      act: (bloc) {
        bloc.add(const PlaylistUpdated(
          tracks: [
            {'title': 'Song 1', 'source': '/path/1.mp3'},
          ],
          currentIndex: 0,
        ));
        bloc.add(const PlaylistUpdated(
          tracks: [],
          currentIndex: 0,
        ));
      },
      expect: () => [
        isA<DiscoveryState>().having(
          (s) => s.playlistTracks.length,
          'tracks',
          1,
        ),
        isA<DiscoveryState>().having(
          (s) => s.playlistTracks.length,
          'tracks',
          0,
        ),
      ],
    );
  });

  // ── SyncQuality Enum ──

  group('SyncQuality enum', () {
    test('labels are correct', () {
      expect(SyncQuality.unknown.label, 'Inconnu');
      expect(SyncQuality.excellent.label, 'Excellent');
      expect(SyncQuality.good.label, 'Bon');
      expect(SyncQuality.acceptable.label, 'Acceptable');
      expect(SyncQuality.degraded.label, 'Dégradé');
    });
  });

  // ── ConnectionDetail Enum ──

  group('ConnectionDetail enum', () {
    test('labels are correct', () {
      expect(ConnectionDetail.idle.label, 'Inactif');
      expect(ConnectionDetail.connecting.label, 'Connexion...');
      expect(ConnectionDetail.synchronizing.label, 'Synchronisation...');
      expect(ConnectionDetail.connected.label, 'Connecté');
      expect(ConnectionDetail.reconnecting.label, 'Reconnexion...');
      expect(ConnectionDetail.fileTransferring.label, 'Transfert de fichier...');
      expect(ConnectionDetail.error.label, 'Erreur');
    });
  });

  // ── DiscoveryState ──

  group('DiscoveryState', () {
    test('copyWith preserves unchanged fields', () {
      const original = DiscoveryState(
        status: DiscoveryStatus.scanning,
        role: DeviceRole.host,
        isPlaying: true,
      );
      final modified = original.copyWith(isPlaying: false);
      expect(modified.status, DiscoveryStatus.scanning);
      expect(modified.role, DeviceRole.host);
      expect(modified.isPlaying, false);
    });

    test('copyWith clearTrack sets track to null', () {
      final track = AudioTrack(
        id: 'track-2',
        title: 'Test',
        source: '/test.mp3',
        sourceType: AudioSourceType.localFile,
      );
      final state = DiscoveryState(currentTrack: track);
      expect(state.currentTrack, isNotNull);
      final cleared = state.copyWith(clearTrack: true);
      expect(cleared.currentTrack, isNull);
    });

    test('copyWith clearFileTransferProgress sets progress to null', () {
      const state = DiscoveryState(fileTransferProgress: 0.5);
      expect(state.fileTransferProgress, 0.5);
      final cleared = state.copyWith(clearFileTransferProgress: true);
      expect(cleared.fileTransferProgress, isNull);
    });

    test('copyWith errorMessage is cleared when not provided', () {
      const state = DiscoveryState(errorMessage: 'Some error');
      final cleared = state.copyWith(status: DiscoveryStatus.idle);
      expect(cleared.errorMessage, isNull);
    });
  });
}
