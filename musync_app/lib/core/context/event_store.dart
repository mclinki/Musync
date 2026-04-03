import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/session_context.dart';
import '../models/audio_session.dart';

/// Types of session events for Event Sourcing.
enum EventType {
  sessionCreated,
  deviceJoined,
  deviceLeft,
  clockSynced,
  trackPrepared,
  playbackStarted,
  playbackPaused,
  playbackResumed,
  playbackStopped,
  trackChanged,
  volumeChanged,
  playlistUpdated,
  contextSnapshot;
}

/// A single immutable session event.
class SessionEvent {
  final int? id;
  final String sessionId;
  final EventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const SessionEvent({
    this.id,
    required this.sessionId,
    required this.type,
    this.data = const {},
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'type': type.name,
        'data': data.isEmpty ? '{}' : jsonEncode(data),
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory SessionEvent.fromMap(Map<String, dynamic> map) {
    return SessionEvent(
      id: map['id'] as int?,
      sessionId: map['session_id'] as String,
      type: EventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => EventType.sessionCreated,
      ),
      data: () {
        try {
          final raw = map['data'];
          if (raw == null || raw == '{}') return <String, dynamic>{};
          return jsonDecode(raw as String) as Map<String, dynamic>;
        } catch (e) {
          return <String, dynamic>{};
        }
      }(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          map['timestamp'] as int? ?? 0),
    );
  }
}

/// A snapshot of context at a point in time.
class ContextSnapshot {
  final int? id;
  final String sessionId;
  final SessionContext context;
  final DateTime createdAt;

  const ContextSnapshot({
    this.id,
    required this.sessionId,
    required this.context,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'context_json': jsonEncode(context.toJson()),
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

/// SQLite-backed event store for Event Sourcing.
///
/// Stores session events and context snapshots.
/// Enables context reconstruction by replaying events
/// since the last snapshot.
class EventStore {
  static const _dbName = 'musync_context.db';
  static const _dbVersion = 1;
  static const _eventsTable = 'session_events';
  static const _snapshotsTable = 'context_snapshots';

  final Logger _logger;
  Database? _db;

  EventStore({Logger? logger}) : _logger = logger ?? Logger();

  /// Initialize the database.
  /// CRIT-006 fix: sqflite only works on Android/iOS, skip on desktop/web.
  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _logger.i('EventStore: sqflite not supported on ${Platform.operatingSystem}, using in-memory store');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
    );

    _logger.i('EventStore initialized at $path');
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_eventsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        data TEXT NOT NULL DEFAULT '{}',
        timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_snapshotsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        context_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_events_session ON $_eventsTable (session_id, timestamp)');
    await db.execute(
        'CREATE INDEX idx_snapshots_session ON $_snapshotsTable (session_id, created_at)');

    _logger.i('EventStore tables created');
  }

  /// Append an event to the store.
  Future<void> append(SessionEvent event) async {
    if (_db == null) {
      _logger.w('EventStore not initialized, skipping event');
      return;
    }
    await _db!.insert(_eventsTable, event.toMap());
  }

  /// Get events for a session, optionally filtered by time.
  Future<List<SessionEvent>> getEvents({
    String? sessionId,
    int limit = 50,
    DateTime? since,
  }) async {
    if (_db == null) return [];

    String where = '';
    List<dynamic> whereArgs = [];

    if (sessionId != null) {
      where = 'session_id = ?';
      whereArgs.add(sessionId);
    }

    if (since != null) {
      where += where.isEmpty ? '' : ' AND ';
      where += 'timestamp >= ?';
      whereArgs.add(since.millisecondsSinceEpoch);
    }

    final maps = await _db!.query(
      _eventsTable,
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    return maps.map((m) => SessionEvent.fromMap(m)).toList();
  }

  /// Save a context snapshot.
  Future<void> saveSnapshot(ContextSnapshot snapshot) async {
    if (_db == null) return;

    // Delete older snapshots for this session (keep only latest)
    await _db!.delete(
      _snapshotsTable,
      where: 'session_id = ?',
      whereArgs: [snapshot.sessionId],
    );

    await _db!.insert(_snapshotsTable, {
      'session_id': snapshot.sessionId,
      'context_json': jsonEncode(snapshot.context.toJson()),
      'created_at': snapshot.createdAt.millisecondsSinceEpoch,
    });

    _logger.d('Snapshot saved for session ${snapshot.sessionId}');
  }

  /// Get the latest snapshot for a session.
  Future<ContextSnapshot?> getLatestSnapshot(String sessionId) async {
    if (_db == null) return null;

    final maps = await _db!.query(
      _snapshotsTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    final contextJson = map['context_json'] as String?;
    SessionContext context;
    if (contextJson != null) {
      try {
        final decoded = jsonDecode(contextJson) as Map<String, dynamic>;
        context = SessionContext.fromJson(decoded);
      } catch (e) {
        _logger.w('Failed to deserialize context snapshot: $e');
        context = SessionContext.empty(sessionId: sessionId);
      }
    } else {
      context = SessionContext.empty(sessionId: sessionId);
    }

    return ContextSnapshot(
      id: map['id'] as int?,
      sessionId: map['session_id'] as String,
      context: context,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int? ?? 0),
    );
  }

  /// Get events since the last snapshot.
  Future<List<SessionEvent>> getEventsSinceLastSnapshot(
      String sessionId) async {
    final snapshot = await getLatestSnapshot(sessionId);
    return getEvents(
      sessionId: sessionId,
      since: snapshot?.createdAt,
    );
  }

  /// Clear all data for a session.
  Future<void> clearSession(String sessionId) async {
    if (_db == null) return;
    await _db!.delete(_eventsTable,
        where: 'session_id = ?', whereArgs: [sessionId]);
    await _db!.delete(_snapshotsTable,
        where: 'session_id = ?', whereArgs: [sessionId]);
    _logger.d('Cleared data for session $sessionId');
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}
