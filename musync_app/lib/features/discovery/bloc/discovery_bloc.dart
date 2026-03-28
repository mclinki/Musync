import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
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

class SyncQualityChanged extends DiscoveryEvent {
  final SyncQuality quality;
  final double offsetMs;

  const SyncQualityChanged({
    required this.quality,
    required this.offsetMs,
  });

  @override
  List<Object?> get props => [quality, offsetMs];
}

class FileTransferProgressChanged extends DiscoveryEvent {
  final double progress;

  const FileTransferProgressChanged(this.progress);

  @override
  List<Object?> get props => [progress];
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
  // Host info for slave view
  final DeviceInfo? hostDevice;
  // Sync quality
  final SyncQuality syncQuality;
  final double syncOffsetMs;
  // File transfer progress (0.0 to 1.0)
  final double? fileTransferProgress;
  // Connection state detail
  final ConnectionDetail connectionDetail;

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
    this.hostDevice,
    this.syncQuality = SyncQuality.unknown,
    this.syncOffsetMs = 0,
    this.fileTransferProgress,
    this.connectionDetail = ConnectionDetail.idle,
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
    DeviceInfo? hostDevice,
    SyncQuality? syncQuality,
    double? syncOffsetMs,
    double? fileTransferProgress,
    bool clearFileTransferProgress = false,
    ConnectionDetail? connectionDetail,
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
      hostDevice: hostDevice ?? this.hostDevice,
      syncQuality: syncQuality ?? this.syncQuality,
      syncOffsetMs: syncOffsetMs ?? this.syncOffsetMs,
      fileTransferProgress: clearFileTransferProgress
          ? null
          : (fileTransferProgress ?? this.fileTransferProgress),
      connectionDetail: connectionDetail ?? this.connectionDetail,
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
        hostDevice,
        syncQuality,
        syncOffsetMs,
        fileTransferProgress,
        connectionDetail,
      ];
}

enum SyncQuality {
  unknown,
  excellent,
  good,
  acceptable,
  degraded;

  String get label {
    switch (this) {
      case SyncQuality.unknown:
        return 'Inconnu';
      case SyncQuality.excellent:
        return 'Excellent';
      case SyncQuality.good:
        return 'Bon';
      case SyncQuality.acceptable:
        return 'Acceptable';
      case SyncQuality.degraded:
        return 'Dégradé';
    }
  }

  Color get color {
    switch (this) {
      case SyncQuality.unknown:
        return Colors.grey;
      case SyncQuality.excellent:
        return Colors.green;
      case SyncQuality.good:
        return Colors.lightGreen;
      case SyncQuality.acceptable:
        return Colors.orange;
      case SyncQuality.degraded:
        return Colors.red;
    }
  }
}

enum ConnectionDetail {
  idle,
  connecting,
  synchronizing,
  connected,
  reconnecting,
  fileTransferring,
  error;

  String get label {
    switch (this) {
      case ConnectionDetail.idle:
        return 'Inactif';
      case ConnectionDetail.connecting:
        return 'Connexion...';
      case ConnectionDetail.synchronizing:
        return 'Synchronisation...';
      case ConnectionDetail.connected:
        return 'Connecté';
      case ConnectionDetail.reconnecting:
        return 'Reconnexion...';
      case ConnectionDetail.fileTransferring:
        return 'Transfert de fichier...';
      case ConnectionDetail.error:
        return 'Erreur';
    }
  }
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
    on<SyncQualityChanged>(_onSyncQualityChanged);
    on<FileTransferProgressChanged>(_onFileTransferProgressChanged);

    // Listen to session manager
    _devicesSub = sessionManager.devicesStream.listen((devices) {
      // Sync available devices from session manager
      final currentIds = state.availableDevices.map((d) => d.id).toSet();
      for (final device in devices) {
        if (!currentIds.contains(device.id)) {
          add(DeviceFound(device));
        }
      }
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
    emit(state.copyWith(
      status: DiscoveryStatus.joining,
      errorMessage: null,
      hostDevice: event.hostDevice,
      connectionDetail: ConnectionDetail.connecting,
    ));
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
          connectionDetail: ConnectionDetail.error,
        ));
      }
    } catch (e) {
      _logger.e('Failed to join session: $e');
      emit(state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: 'Failed to join session: $e',
        connectionDetail: ConnectionDetail.error,
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
      connectionDetail: ConnectionDetail.connected,
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

  void _onSyncQualityChanged(
    SyncQualityChanged event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      syncQuality: event.quality,
      syncOffsetMs: event.offsetMs,
    ));
  }

  void _onFileTransferProgressChanged(
    FileTransferProgressChanged event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      fileTransferProgress: event.progress,
      connectionDetail: event.progress < 1.0
          ? ConnectionDetail.fileTransferring
          : ConnectionDetail.connected,
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
