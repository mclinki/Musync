import 'dart:async';
import 'package:logger/logger.dart';
import '../models/session_context.dart';
import '../models/audio_session.dart';
import 'event_store.dart';

/// Orchestrates session context management.
///
/// Provides:
/// - Event recording (append to EventStore + update in-memory context)
/// - Snapshot creation (periodic or on-demand)
/// - Context restoration (snapshot + event replay)
/// - Read-only summary for agent IA
class ContextManager {
  final EventStore _eventStore;
  final Logger _logger;

  SessionContext? _currentContext;

  ContextManager({
    required EventStore eventStore,
    Logger? logger,
  })  : _eventStore = eventStore,
        _logger = logger ?? Logger();

  /// Current context (read-only).
  SessionContext? get currentContext => _currentContext;

  /// Whether a context is active.
  bool get hasContext => _currentContext != null;

  /// Initialize context for a new session.
  void initContext(String sessionId) {
    _currentContext = SessionContext.empty(sessionId: sessionId);
    _logger.i('Context initialized for session $sessionId');
  }

  /// Clear the current context.
  void clearContext() {
    _currentContext = null;
    _logger.d('Context cleared');
  }

  /// Record an event and update the in-memory context.
  Future<void> recordEvent(SessionEvent event) async {
    await _eventStore.append(event);
    _currentContext = _applyEvent(_currentContext, event);
    _logger.d('Event recorded: ${event.type.name}');
  }

  /// Create a snapshot of the current context.
  Future<ContextSnapshot?> createSnapshot() async {
    if (_currentContext == null) {
      _logger.w('No active context to snapshot');
      return null;
    }

    final snapshot = ContextSnapshot(
      sessionId: _currentContext!.sessionId,
      context: _currentContext!,
      createdAt: DateTime.now(),
    );

    await _eventStore.saveSnapshot(snapshot);
    _logger.i('Snapshot created for session ${_currentContext!.sessionId}');
    return snapshot;
  }

  /// Restore context from the last snapshot + event replay.
  Future<SessionContext?> restoreContext(String sessionId) async {
    final snapshot = await _eventStore.getLatestSnapshot(sessionId);

    SessionContext context;
    if (snapshot != null) {
      context = snapshot.context;
      _logger.d('Restored from snapshot (${snapshot.createdAt})');
    } else {
      context = SessionContext.empty(sessionId: sessionId);
      _logger.d('No snapshot found, starting from empty context');
    }

    // Replay events since snapshot
    final events = await _eventStore.getEvents(
      sessionId: sessionId,
      since: snapshot?.createdAt,
    );

    for (final event in events) {
      context = _applyEvent(context, event);
    }

    _currentContext = context;
    _logger.i(
        'Context restored: ${events.length} events replayed for session $sessionId');
    return context;
  }

  /// Get a text summary of the current context (for agent IA).
  String getContextSummary() {
    if (_currentContext == null) return 'Aucune session active.';
    return _currentContext!.summary;
  }

  /// Get recent events for diagnostics.
  Future<List<SessionEvent>> getRecentEvents({
    int limit = 50,
  }) async {
    if (_currentContext == null) return [];
    return _eventStore.getEvents(
      sessionId: _currentContext!.sessionId,
      limit: limit,
    );
  }

  /// Apply an event to a context (pure function).
  SessionContext _applyEvent(SessionContext? context, SessionEvent event) {
    if (context == null) {
      return SessionContext(
        sessionId: event.sessionId,
        state: SessionState.waiting,
        createdAt: event.timestamp,
        updatedAt: event.timestamp,
      );
    }

    switch (event.type) {
      case EventType.deviceJoined:
        return context.copyWith(state: SessionState.syncing);
      case EventType.deviceLeft:
        return context; // Devices updated externally
      case EventType.playbackStarted:
        return context.copyWith(
          state: SessionState.playing,
          currentTrack: event.data['track'] != null
              ? AudioTrack.fromJson(
                  Map<String, dynamic>.from(event.data['track'] as Map))
              : context.currentTrack,
        );
      case EventType.playbackPaused:
        return context.copyWith(
          state: SessionState.paused,
          positionMs:
              (event.data['position_ms'] as num?)?.toInt() ??
                  context.positionMs,
        );
      case EventType.playbackResumed:
        return context.copyWith(state: SessionState.playing);
      case EventType.playbackStopped:
        return context.copyWith(
          state: SessionState.waiting,
          positionMs: 0,
        );
      case EventType.trackChanged:
        final trackData = event.data['track'];
        return context.copyWith(
          currentTrack: trackData != null
              ? AudioTrack.fromJson(
                  Map<String, dynamic>.from(trackData as Map))
              : null,
          positionMs: 0,
        );
      case EventType.volumeChanged:
        return context.copyWith(
          volume:
              (event.data['volume'] as num?)?.toDouble() ?? context.volume,
        );
      case EventType.playlistUpdated:
        return context; // Playlist updated externally
      case EventType.clockSynced:
        return context; // Clock offsets updated externally
      default:
        return context;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _currentContext = null;
  }
}
