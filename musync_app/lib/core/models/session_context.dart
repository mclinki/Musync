import 'package:equatable/equatable.dart';
import 'audio_session.dart';
import 'device_info.dart';

/// Current version of the context schema.
/// Increment on structural changes.
const int currentContextVersion = 2;

/// Serializable snapshot of a session's full state.
///
/// Used for:
/// - Event Sourcing (append events, reconstruct state)
/// - Context reconnection (slave restores state after disconnect)
/// - Agent IA context (read-only summary of session state)
///
/// Versioned schema with automatic migration from older versions.
class SessionContext extends Equatable {
  final int version;
  final String sessionId;
  final SessionState state;
  final AudioTrack? currentTrack;
  final int positionMs;
  final double volume;
  final List<DeviceInfo> devices;
  final List<AudioTrack> playlist;
  final int currentIndex;
  final Map<String, double> volumes;
  final Map<String, double> clockOffsets;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionContext({
    this.version = currentContextVersion,
    required this.sessionId,
    required this.state,
    this.currentTrack,
    this.positionMs = 0,
    this.volume = 1.0,
    this.devices = const [],
    this.playlist = const [],
    this.currentIndex = 0,
    this.volumes = const {},
    this.clockOffsets = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create an empty context for a new session.
  factory SessionContext.empty({required String sessionId}) {
    final now = DateTime.now();
    return SessionContext(
      sessionId: sessionId,
      state: SessionState.waiting,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Serialize to JSON with version tag.
  Map<String, dynamic> toJson() => {
        'version': version,
        'session_id': sessionId,
        'state': state.name,
        'current_track': currentTrack?.toJson(),
        'position_ms': positionMs,
        'volume': volume,
        'devices': devices.map((d) => d.toJson()).toList(),
        'playlist': playlist.map((t) => t.toJson()).toList(),
        'current_index': currentIndex,
        'volumes': volumes,
        'clock_offsets': clockOffsets,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Deserialize from JSON with automatic version migration.
  factory SessionContext.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    final migrated = _migrate(json, fromVersion: version);

    return SessionContext(
      version: currentContextVersion,
      sessionId: migrated['session_id'] as String,
      state: SessionState.values.firstWhere(
        (e) => e.name == migrated['state'],
        orElse: () => SessionState.waiting,
      ),
      currentTrack: migrated['current_track'] != null
          ? AudioTrack.fromJson(
              Map<String, dynamic>.from(migrated['current_track']))
          : null,
      positionMs: (merged_num(migrated, 'position_ms') ?? 0).toInt(),
      volume: (merged_num(migrated, 'volume') ?? 1.0).toDouble(),
      devices: (migrated['devices'] as List?)
              ?.map((d) =>
                  DeviceInfo.fromJson(Map<String, dynamic>.from(d as Map)))
              .toList() ??
          [],
      playlist: (migrated['playlist'] as List?)
              ?.map((t) =>
                  AudioTrack.fromJson(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
      currentIndex: (merged_num(migrated, 'current_index') ?? 0).toInt(),
      volumes: (migrated['volumes'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ) ??
          {},
      clockOffsets: (migrated['clock_offsets'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ) ??
          {},
      createdAt: DateTime.tryParse(
              migrated['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
              migrated['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Progressive schema migration.
  static Map<String, dynamic> _migrate(
    Map<String, dynamic> json, {
    required int fromVersion,
  }) {
    var result = Map<String, dynamic>.from(json);

    // v1 → v2: add volumes + clock_offsets
    if (fromVersion < 2) {
      result['volumes'] = <String, double>{};
      result['clock_offsets'] = <String, double>{};
    }

    // Future: v2 → v3
    // if (fromVersion < 3) { ... }

    return result;
  }

  /// Immutable copy with modifications.
  SessionContext copyWith({
    SessionState? state,
    AudioTrack? currentTrack,
    bool clearTrack = false,
    int? positionMs,
    double? volume,
    List<DeviceInfo>? devices,
    List<AudioTrack>? playlist,
    int? currentIndex,
    Map<String, double>? volumes,
    Map<String, double>? clockOffsets,
  }) {
    return SessionContext(
      version: version,
      sessionId: sessionId,
      state: state ?? this.state,
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      positionMs: positionMs ?? this.positionMs,
      volume: volume ?? this.volume,
      devices: devices ?? this.devices,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      volumes: volumes ?? this.volumes,
      clockOffsets: clockOffsets ?? this.clockOffsets,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Human-readable summary for agent IA or debugging.
  String get summary => '''
Session: $sessionId
État: ${state.label}
Piste: ${currentTrack?.title ?? 'Aucune'}
Position: ${(positionMs / 1000).toStringAsFixed(1)}s
Appareils: ${devices.length}
Playlist: ${playlist.length} pistes (index $currentIndex)
Volume: ${(volume * 100).round()}%
''';

  @override
  List<Object?> get props => [
        version,
        sessionId,
        state,
        currentTrack,
        positionMs,
        volume,
        devices,
        playlist,
        currentIndex,
        volumes,
        clockOffsets,
      ];
}

/// Helper to safely extract num from migrated JSON.
num? merged_num(Map<String, dynamic> json, String key) {
  final val = json[key];
  if (val is num) return val;
  return null;
}
