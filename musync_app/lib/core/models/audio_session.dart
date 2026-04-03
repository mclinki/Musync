import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../app_constants.dart';
import '../utils/format.dart';
import 'device_info.dart';

/// Represents a multi-device audio session.
class AudioSession extends Equatable {
  final String sessionId;
  final String name;
  final DeviceInfo hostDevice;
  final List<DeviceInfo> slaves;
  final SessionState state;
  final AudioTrack? currentTrack;
  final DateTime createdAt;
  final DateTime? startedAt;

  const AudioSession({
    required this.sessionId,
    required this.name,
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
      name: 'Session_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      hostDevice: host,
      createdAt: DateTime.now(),
    );
  }

  AudioSession copyWith({
    String? sessionId,
    String? name,
    DeviceInfo? hostDevice,
    List<DeviceInfo>? slaves,
    SessionState? state,
    AudioTrack? currentTrack,
    bool clearTrack = false,
    DateTime? createdAt,
    DateTime? startedAt,
  }) {
    return AudioSession(
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      hostDevice: hostDevice ?? this.hostDevice,
      slaves: slaves ?? this.slaves,
      state: state ?? this.state,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  int get totalDevices => 1 + slaves.length;

  bool get isFull => slaves.length >= AppConstants.maxSlaves;

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
        'name': name,
        'host': hostDevice.toJson(),
        'slaves': slaves.map((d) => d.toJson()).toList(),
        'state': state.name,
        'track': currentTrack?.toJson(),
        'created_at': createdAt.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        sessionId,
        name,
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
    final fileName = extractFileName(path);
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    final pathHash = path.hashCode.abs().toRadixString(16).padLeft(8, '0');
    final deterministicId = 'track_$pathHash';

    return AudioTrack(
      id: deterministicId,
      title: nameWithoutExt,
      source: path,
      sourceType: AudioSourceType.localFile,
    );
  }

  static Future<AudioTrack> fromFilePathWithMetadata(String path) async {
    final fileName = extractFileName(path);
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final pathHash = path.hashCode.abs().toRadixString(16).padLeft(8, '0');
    final deterministicId = 'track_$pathHash';

    String title = nameWithoutExt;
    String? artist;
    String? album;
    int? durationMs;

    if (!Platform.isWindows) {
      try {
        final file = File(path);
        final metadata = await readMetadata(file);

        title = metadata.title?.isNotEmpty == true
            ? metadata.title!
            : nameWithoutExt;
        artist = metadata.artist?.isNotEmpty == true
            ? metadata.artist
            : null;
        album = metadata.album?.isNotEmpty == true
            ? metadata.album
            : null;
        // audio_metadata_reader doesn't provide duration
        durationMs = null;
      } catch (e) {
        // Metadata extraction failed, use filename as fallback
        title = nameWithoutExt;
      }
    }

    return AudioTrack(
      id: deterministicId,
      title: title,
      artist: artist,
      album: album,
      source: path,
      sourceType: AudioSourceType.localFile,
      durationMs: durationMs,
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
        'file_size_bytes': fileSizeBytes,
      };

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      source: json['source'] as String? ?? '',
      sourceType: AudioSourceType.values.firstWhere(
        (e) => e.name == json['source_type'],
        orElse: () => AudioSourceType.localFile,
      ),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [id, title, source, sourceType];
}

enum AudioSourceType {
  localFile,
  url,
}
