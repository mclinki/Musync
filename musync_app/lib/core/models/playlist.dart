import 'package:equatable/equatable.dart';
import 'audio_session.dart';

enum RepeatMode { off, one, all }

/// Manages a queue of audio tracks for sequential playback.
class Playlist extends Equatable {
  final List<AudioTrack> tracks;
  final int currentIndex;
  final RepeatMode repeatMode;
  final bool isShuffled;

  const Playlist({
    this.tracks = const [],
    this.currentIndex = 0,
    this.repeatMode = RepeatMode.off,
    this.isShuffled = false,
  });

  /// Whether the queue is empty.
  bool get isEmpty => tracks.isEmpty;

  /// Whether the queue has tracks.
  bool get isNotEmpty => tracks.isNotEmpty;

  /// Number of tracks in the queue.
  int get length => tracks.length;

  /// Current track being played (or null if empty).
  AudioTrack? get currentTrack =>
      tracks.isNotEmpty && currentIndex < tracks.length
          ? tracks[currentIndex]
          : null;

  /// Whether there is a next track.
  bool get hasNext => currentIndex < tracks.length - 1;

  /// Whether there is a previous track.
  bool get hasPrevious => currentIndex > 0;

  /// Next track (or null if at end).
  AudioTrack? get nextTrack => hasNext ? tracks[currentIndex + 1] : null;

  /// Previous track (or null if at beginning).
  AudioTrack? get previousTrack =>
      hasPrevious ? tracks[currentIndex - 1] : null;

  /// Add a track to the end of the queue.
  Playlist addTrack(AudioTrack track) {
    return copyWith(tracks: [...tracks, track]);
  }

  /// Add multiple tracks to the end of the queue.
  Playlist addTracks(List<AudioTrack> newTracks) {
    return copyWith(tracks: [...tracks, ...newTracks]);
  }

  /// Insert a track at a specific position.
  Playlist insertTrack(int index, AudioTrack track) {
    final newTracks = List<AudioTrack>.from(tracks);
    newTracks.insert(index.clamp(0, tracks.length), track);
    return copyWith(tracks: newTracks);
  }

  /// Remove a track at a specific index.
  Playlist removeTrack(int index) {
    if (index < 0 || index >= tracks.length) return this;
    final newTracks = List<AudioTrack>.from(tracks)..removeAt(index);
    final newIndex = currentIndex >= newTracks.length
        ? (newTracks.length - 1).clamp(0, newTracks.length)
        : currentIndex;
    return copyWith(tracks: newTracks, currentIndex: newIndex);
  }

  /// Move to the next track. Returns the new playlist.
  /// Returns null if there is no next track.
  Playlist? skipNext() {
    if (!hasNext) return null;
    return copyWith(currentIndex: currentIndex + 1);
  }

  /// Move to the previous track. Returns the new playlist.
  /// Returns null if there is no previous track.
  Playlist? skipPrevious() {
    if (!hasPrevious) return null;
    return copyWith(currentIndex: currentIndex - 1);
  }

  /// Jump to a specific track index.
  Playlist goTo(int index) {
    if (index < 0 || index >= tracks.length) return this;
    return copyWith(currentIndex: index);
  }

  /// Clear all tracks.
  Playlist clear() {
    return const Playlist();
  }

  /// Shuffle the playlist (keeping current track at position 0).
  Playlist? shuffle() {
    if (tracks.length <= 1) return null;
    final current = currentTrack;
    final others = List<AudioTrack>.from(tracks);
    if (current != null) {
      others.removeAt(currentIndex);
    }
    others.shuffle();
    if (current != null) {
      others.insert(0, current);
    }
    return Playlist(
      tracks: others,
      currentIndex: 0,
      repeatMode: repeatMode,
      isShuffled: true,
    );
  }

  /// Cycle through repeat modes: off → all → one → off
  Playlist toggleRepeat() {
    final nextMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    return copyWith(repeatMode: nextMode);
  }

  Playlist copyWith({
    List<AudioTrack>? tracks,
    int? currentIndex,
    RepeatMode? repeatMode,
    bool? isShuffled,
  }) {
    return Playlist(
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffled: isShuffled ?? this.isShuffled,
    );
  }

  @override
  List<Object?> get props => [tracks, currentIndex, repeatMode, isShuffled];

  /// Sérialiser la playlist en JSON.
  Map<String, dynamic> toJson() {
    return {
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'currentIndex': currentIndex,
      'repeatMode': repeatMode.name,
      'isShuffled': isShuffled,
    };
  }

  /// Désérialiser depuis JSON.
  factory Playlist.fromJson(Map<String, dynamic> json) {
    final tracksJson = json['tracks'] as List? ?? [];
    final tracks = tracksJson
        .whereType<Map<String, dynamic>>()
        .map((t) => AudioTrack.fromJson(t))
        .toList();
    final currentIndex = (json['currentIndex'] as num?)?.toInt() ?? 0;
    final repeatModeName = json['repeatMode'] as String?;
    final repeatMode = repeatModeName != null
        ? RepeatMode.values.byName(repeatModeName)
        : RepeatMode.off;
    final isShuffled = json['isShuffled'] as bool? ?? false;
    return Playlist(
      tracks: tracks,
      currentIndex: currentIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1),
      repeatMode: repeatMode,
      isShuffled: isShuffled,
    );
  }
}
