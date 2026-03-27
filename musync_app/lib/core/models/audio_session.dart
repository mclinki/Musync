import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'device_info.dart';

/// Represents a multi-device audio session.
class AudioSession extends Equatable {
  final String sessionId;
  final DeviceInfo hostDevice;
  final List<DeviceInfo> slaves;
  final SessionState state;
  final AudioTrack? currentTrack;
  final DateTime createdAt;
  final DateTime? startedAt;

  const AudioSession({
    required this.sessionId,
    required this.hostDevice,
    this.slaves = const [],
    this.state = SessionState.waiting,
    this.currentTrack,
    required this.createdAt,
    this.startedAt,
  });

  factory AudioSession.create({required DeviceInfo host}) {
    return AudioSession(
      sessionId: const Uuid().v4(),
      hostDevice: host,
      createdAt: DateTime.now(),
    );
  }

  AudioSession copyWith({
    String? sessionId,
    DeviceInfo? hostDevice,
    List<DeviceInfo>? slaves,
    SessionState? state,
    AudioTrack? currentTrack,
    DateTime? createdAt,
    DateTime? startedAt,
  }) {
    return AudioSession(
      sessionId: sessionId ?? this.sessionId,
      hostDevice: hostDevice ?? this.hostDevice,
      slaves: slaves ?? this.slaves,
      state: state ?? this.state,
      currentTrack: currentTrack ?? this.currentTrack,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  int get totalDevices => 1 + slaves.length;

  bool get isFull => slaves.length >= 8;

  bool hasDevice(String deviceId) {
    return hostDevice.id == deviceId ||
        slaves.any((d) => d.id == deviceId);
  }

  AudioSession addSlave(DeviceInfo device) {
    if (isFull || hasDevice(device.id)) return this;
    return copyWith(slaves: [...slaves, device]);
  }

  AudioSession removeSlave(String deviceId) {
    return copyWith(
      slaves: slaves.where((d) => d.id != deviceId).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'host': hostDevice.toJson(),
        'slaves': slaves.map((d) => d.toJson()).toList(),
        'state': state.name,
        'track': currentTrack?.toJson(),
      };

  @override
  List<Object?> get props => [
        sessionId,
        hostDevice,
        slaves,
        state,
        currentTrack,
      ];
}

enum SessionState {
  waiting,
  syncing,
  playing,
  paused,
  buffering,
  error;

  String get label {
    switch (this) {
      case SessionState.waiting:
        return 'En attente';
      case SessionState.syncing:
        return 'Synchronisation...';
      case SessionState.playing:
        return 'En lecture';
      case SessionState.paused:
        return 'En pause';
      case SessionState.buffering:
        return 'Chargement...';
      case SessionState.error:
        return 'Erreur';
    }
  }
}

/// Represents an audio track being played.
class AudioTrack extends Equatable {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String source; // file path or URL
  final AudioSourceType sourceType;
  final int? durationMs;
  final int? fileSizeBytes;

  const AudioTrack({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.source,
    required this.sourceType,
    this.durationMs,
    this.fileSizeBytes,
  });

  factory AudioTrack.fromFilePath(String path) {
    final fileName = path.split('/').last.split('\\').last;
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    return AudioTrack(
      id: const Uuid().v4(),
      title: nameWithoutExt,
      source: path,
      sourceType: AudioSourceType.localFile,
    );
  }

  factory AudioTrack.fromUrl(String url, {String? title}) {
    return AudioTrack(
      id: const Uuid().v4(),
      title: title ?? 'Stream',
      source: url,
      sourceType: AudioSourceType.url,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'source': source,
        'source_type': sourceType.name,
        'duration_ms': durationMs,
      };

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      source: json['source'] as String,
      sourceType: AudioSourceType.values.firstWhere(
        (e) => e.name == json['source_type'],
        orElse: () => AudioSourceType.localFile,
      ),
      durationMs: json['duration_ms'] as int?,
    );
  }

  @override
  List<Object?> get props => [id, title, source, sourceType];
}

enum AudioSourceType {
  localFile,
  url,
}
