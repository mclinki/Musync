import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../core/core.dart';

// ── Events ──

abstract class DiscoveryEvent extends Equatable {
  const DiscoveryEvent();

  @override
  List<Object?> get props => [];
}

class StartScanning extends DiscoveryEvent {
  const StartScanning();
}

class StopScanning extends DiscoveryEvent {
  const StopScanning();
}

class DeviceFound extends DiscoveryEvent {
  final DeviceInfo device;

  const DeviceFound(this.device);

  @override
  List<Object?> get props => [device];
}

class DeviceLost extends DiscoveryEvent {
  final String deviceId;

  const DeviceLost(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class HostSessionRequested extends DiscoveryEvent {
  const HostSessionRequested();
}

class JoinSessionRequested extends DiscoveryEvent {
  final DeviceInfo hostDevice;

  const JoinSessionRequested(this.hostDevice);

  @override
  List<Object?> get props => [hostDevice];
}

class SessionCreated extends DiscoveryEvent {
  final String sessionId;

  const SessionCreated(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

class SessionJoined extends DiscoveryEvent {
  const SessionJoined();
}

class LeaveSessionRequested extends DiscoveryEvent {
  const LeaveSessionRequested();
}

class SessionStateChanged extends DiscoveryEvent {
  final SessionManagerState state;

  const SessionStateChanged(this.state);

  @override
  List<Object?> get props => [state];
}

class PlaybackStateChanged extends DiscoveryEvent {
  final AudioTrack? track;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;

  const PlaybackStateChanged({
    this.track,
    required this.isPlaying,
    required this.position,
    this.duration,
  });

  @override
  List<Object?> get props => [track, isPlaying, position, duration];
}

// ── State ──

class DiscoveryState extends Equatable {
  final DiscoveryStatus status;
  final List<DeviceInfo> availableDevices;
  final String? currentSessionId;
  final DeviceRole role;
  final String? errorMessage;
  final int connectedDeviceCount;
  // Playback info for slave
  final AudioTrack? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;

  const DiscoveryState({
    this.status = DiscoveryStatus.idle,
    this.availableDevices = const [],
    this.currentSessionId,
    this.role = DeviceRole.none,
    this.errorMessage,
    this.connectedDeviceCount = 0,
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration,
  });

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    List<DeviceInfo>? availableDevices,
    String? currentSessionId,
    DeviceRole? role,
    String? errorMessage,
    int? connectedDeviceCount,
    AudioTrack? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool clearTrack = false,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      availableDevices: availableDevices ?? this.availableDevices,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      role: role ?? this.role,
      errorMessage: errorMessage,
      connectedDeviceCount: connectedDeviceCount ?? this.connectedDeviceCount,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }

  @override
  List<Object?> get props => [
        status,
        availableDevices,
        currentSessionId,
        role,
        errorMessage,
        connectedDeviceCount,
        currentTrack,
        isPlaying,
        position,
        duration,
      ];
}

enum DiscoveryStatus {
  idle,
  scanning,
  hosting,
  joining,
  joined,
  error,
}

// ── BLoC ──

class DiscoveryBloc extends Bloc<DiscoveryEvent, DiscoveryState> {
  final SessionManager sessionManager;
  final Logger _logger;
  StreamSubscription? _devicesSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _audioStateSub;
  StreamSubscription? _positionSub;

  DiscoveryBloc({required this.sessionManager, Logger? logger})
      : _logger = logger ?? Logger(),
        super(const DiscoveryState()) {
    on<StartScanning>(_onStartScanning);
    on<StopScanning>(_onStopScanning);
    on<DeviceFound>(_onDeviceFound);
    on<DeviceLost>(_onDeviceLost);
    on<HostSessionRequested>(_onHostSession);
    on<JoinSessionRequested>(_onJoinSession);
    on<SessionCreated>(_onSessionCreated);
    on<SessionJoined>(_onSessionJoined);
    on<LeaveSessionRequested>(_onLeaveSession);
    on<SessionStateChanged>(_onSessionStateChanged);
    on<PlaybackStateChanged>(_onPlaybackStateChanged);

    // Listen to session manager
    _devicesSub = sessionManager.devicesStream.listen((devices) {
      // Devices are already in discoveredDevices
    });

    _stateSub = sessionManager.stateStream.listen((state) {
      add(SessionStateChanged(state));
    });

    // Listen to audio engine state
    _audioStateSub = sessionManager.audioEngine.stateStream.listen((audioState) {
      _handleAudioStateChange(audioState);
    });

    // Listen to position updates
    _positionSub = sessionManager.audioEngine.positionStream.listen((position) {
      _handlePositionChange(position);
    });
  }

  void _handleAudioStateChange(AudioEngineState audioState) {
    final isPlaying = audioState == AudioEngineState.playing;
    add(PlaybackStateChanged(
      track: sessionManager.audioEngine.currentTrack,
      isPlaying: isPlaying,
      position: sessionManager.audioEngine.position,
      duration: sessionManager.audioEngine.duration,
    ));
  }

  void _handlePositionChange(Duration position) {
    if (state.currentTrack != null) {
      add(PlaybackStateChanged(
        track: state.currentTrack,
        isPlaying: state.isPlaying,
        position: position,
        duration: state.duration,
      ));
    }
  }

  Future<void> _onStartScanning(
    StartScanning event,
    Emitter<DiscoveryState> emit,
  ) async {
    emit(state.copyWith(status: DiscoveryStatus.scanning, errorMessage: null));
    await sessionManager.startScanning();
  }

  Future<void> _onStopScanning(
    StopScanning event,
    Emitter<DiscoveryState> emit,
  ) async {
    await sessionManager.stopScanning();
    emit(state.copyWith(status: DiscoveryStatus.idle));
  }

  void _onDeviceFound(
    DeviceFound event,
    Emitter<DiscoveryState> emit,
  ) {
    final devices = List<DeviceInfo>.from(state.availableDevices);
    final index = devices.indexWhere((d) => d.id == event.device.id);
    if (index >= 0) {
      devices[index] = event.device;
    } else {
      devices.add(event.device);
    }
    emit(state.copyWith(availableDevices: devices));
  }

  void _onDeviceLost(
    DeviceLost event,
    Emitter<DiscoveryState> emit,
  ) {
    final devices = state.availableDevices
        .where((d) => d.id != event.deviceId)
        .toList();
    emit(state.copyWith(availableDevices: devices));
  }

  Future<void> _onHostSession(
    HostSessionRequested event,
    Emitter<DiscoveryState> emit,
  ) async {
    emit(state.copyWith(status: DiscoveryStatus.hosting, errorMessage: null));
    try {
      final sessionId = await sessionManager.hostSession();
      add(SessionCreated(sessionId));
    } catch (e) {
      _logger.e('Failed to host session: $e');
      emit(state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: 'Failed to create session: $e',
      ));
    }
  }

  Future<void> _onJoinSession(
    JoinSessionRequested event,
    Emitter<DiscoveryState> emit,
  ) async {
    emit(state.copyWith(status: DiscoveryStatus.joining, errorMessage: null));
    try {
      final success = await sessionManager.joinSession(
        hostIp: event.hostDevice.ip,
        hostPort: event.hostDevice.port,
      );
      if (success) {
        add(const SessionJoined());
      } else {
        emit(state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: 'Failed to connect to host',
        ));
      }
    } catch (e) {
      _logger.e('Failed to join session: $e');
      emit(state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: 'Failed to join session: $e',
      ));
    }
  }

  void _onSessionCreated(
    SessionCreated event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      status: DiscoveryStatus.hosting,
      currentSessionId: event.sessionId,
      role: DeviceRole.host,
    ));
  }

  void _onSessionJoined(
    SessionJoined event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      status: DiscoveryStatus.joined,
      role: DeviceRole.slave,
    ));
  }

  Future<void> _onLeaveSession(
    LeaveSessionRequested event,
    Emitter<DiscoveryState> emit,
  ) async {
    await sessionManager.leaveSession();
    emit(const DiscoveryState());
  }

  void _onSessionStateChanged(
    SessionStateChanged event,
    Emitter<DiscoveryState> emit,
  ) {
    switch (event.state) {
      case SessionManagerState.idle:
        emit(const DiscoveryState());
        break;
      case SessionManagerState.hosting:
        final session = sessionManager.currentSession;
        emit(state.copyWith(
          status: DiscoveryStatus.hosting,
          role: DeviceRole.host,
          connectedDeviceCount: session?.totalDevices ?? 1,
        ));
        break;
      case SessionManagerState.joined:
        emit(state.copyWith(
          status: DiscoveryStatus.joined,
          role: DeviceRole.slave,
        ));
        break;
      case SessionManagerState.playing:
        // Also update playback state
        emit(state.copyWith(
          isPlaying: true,
        ));
        break;
      case SessionManagerState.paused:
        emit(state.copyWith(
          isPlaying: false,
        ));
        break;
      case SessionManagerState.error:
        emit(state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: 'Session error',
        ));
        break;
      default:
        break;
    }
  }

  void _onPlaybackStateChanged(
    PlaybackStateChanged event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      currentTrack: event.track,
      isPlaying: event.isPlaying,
      position: event.position,
      duration: event.duration,
      clearTrack: event.track == null,
    ));
  }

  @override
  Future<void> close() {
    _devicesSub?.cancel();
    _stateSub?.cancel();
    _audioStateSub?.cancel();
    _positionSub?.cancel();
    return super.close();
  }
}
