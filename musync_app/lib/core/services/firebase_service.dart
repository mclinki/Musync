import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../app_constants.dart';
import '../../firebase_options.dart';

/// Centralized Firebase service for MusyncMIMO.
///
/// Manages:
/// - Firebase initialization
/// - Crashlytics (crash reporting)
/// - Analytics (usage tracking)
/// - Auth (anonymous authentication)
/// - Firestore (session config, saved groups)
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final Logger _logger = Logger();

  bool _initialized = false;
  FirebaseAnalytics? _analytics;
  FirebaseCrashlytics? _crashlytics;
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  // ── Getters ──

  bool get isInitialized => _initialized;
  FirebaseAnalytics? get analytics => _analytics;
  FirebaseCrashlytics? get crashlytics => _crashlytics;
  FirebaseAuth? get auth => _auth;
  FirebaseFirestore? get firestore => _firestore;

  String? get userId => _auth?.currentUser?.uid;

  // ── Initialization ──

  /// Initialize all Firebase services.
  /// Call this once at app startup, before runApp().
  Future<void> initialize() async {
    if (_initialized) {
      _logger.w('Firebase already initialized');
      return;
    }

    // Firebase is not supported on Windows/desktop — skip gracefully
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _logger.i('Firebase not supported on Windows, skipping');
      return;
    }

    try {
      _logger.i('Initializing Firebase...');

      // 1. Core
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _logger.i('Firebase Core initialized');

      // 2. Crashlytics
      _crashlytics = FirebaseCrashlytics.instance;

      // Pass all uncaught Flutter errors to Crashlytics
      FlutterError.onError = _crashlytics!.recordFlutterFatalError;

      // Pass all uncaught async errors to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        _crashlytics!.recordError(error, stack, fatal: true);
        return true;
      };

      _logger.i('Crashlytics initialized');

      // 3. Analytics
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
      _logger.i('Analytics initialized');

      // 4. Auth
      _auth = FirebaseAuth.instance;
      await _signInAnonymously();
      _logger.i('Auth initialized (user: ${_auth!.currentUser?.uid})');

      // 5. Firestore
      _firestore = FirebaseFirestore.instance;
      _logger.i('Firestore initialized');

      _initialized = true;
      _logger.i('Firebase fully initialized');

      // Log app open
      await logEvent('app_open', parameters: {
        'platform': defaultTargetPlatform.name,
      });
    } catch (e, stack) {
      _logger.e('Firebase initialization failed: $e');
      _logger.e(stack.toString());
      // App continues without Firebase — not critical for MVP
    }
  }

  /// Sign in anonymously for tracking without user accounts.
  Future<void> _signInAnonymously() async {
    try {
      if (_auth!.currentUser == null) {
        final credential = await _auth!.signInAnonymously();
        _logger.i('Anonymous sign-in: ${credential.user?.uid}');
      }
    } catch (e) {
      _logger.w('Anonymous sign-in failed: $e');
    }
  }

  // ── Analytics ──

  /// Log a custom analytics event.
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_initialized) return;
    try {
      await _analytics!.logEvent(
        name: name,
        parameters: parameters,
      );
      _logger.d('Analytics: $name $parameters');
    } catch (e) {
      _logger.w('Analytics log failed: $e');
    }
  }

  /// Log session start.
  Future<void> logSessionStart({
    required String sessionId,
    required String role, // 'host' or 'slave'
    required int deviceCount,
  }) async {
    await logEvent('session_start', parameters: {
      'session_id': sessionId,
      'role': role,
      'device_count': deviceCount,
    });
  }

  /// Log session end.
  Future<void> logSessionEnd({
    required String sessionId,
    required int durationSeconds,
    required int deviceCount,
  }) async {
    await logEvent('session_end', parameters: {
      'session_id': sessionId,
      'duration_seconds': durationSeconds,
      'device_count': deviceCount,
    });
  }

  /// Log track play.
  Future<void> logTrackPlay({
    required String trackTitle,
    required String sourceType, // 'localFile' or 'url'
  }) async {
    await logEvent('track_play', parameters: {
      'track_title': trackTitle,
      'source_type': sourceType,
    });
  }

  /// Log device discovery.
  Future<void> logDeviceDiscovered({
    required String deviceType,
    required int discoveryTimeMs,
  }) async {
    await logEvent('device_discovered', parameters: {
      'device_type': deviceType,
      'discovery_time_ms': discoveryTimeMs,
    });
  }

  /// Log sync quality.
  Future<void> logSyncQuality({
    required double offsetMs,
    required double jitterMs,
    required String quality,
  }) async {
    await logEvent('sync_calibration', parameters: {
      'offset_ms': offsetMs,
      'jitter_ms': jitterMs,
      'quality': quality,
    });
  }

  /// Set user property.
  Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    if (!_initialized) return;
    try {
      await _analytics!.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  // ── Crashlytics ──

  /// Record a non-fatal error.
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_initialized) return;
    try {
      await _crashlytics!.recordError(
        exception,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (_) {}
  }

  /// Log a message to Crashlytics.
  Future<void> log(String message) async {
    if (!_initialized) return;
    try {
      await _crashlytics!.log(message);
    } catch (_) {}
  }

  /// Set custom key for Crashlytics.
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_initialized) return;
    try {
      await _crashlytics!.setCustomKey(key, value);
    } catch (_) {}
  }

  // ── Firestore ──

  /// Save a session group to Firestore.
  Future<void> saveGroup({
    required String groupId,
    required String groupName,
    required List<String> deviceIds,
    required List<String> deviceNames,
  }) async {
    if (!_initialized || userId == null) return;
    try {
      await _firestore!
          .collection(AppConstants.firestoreCollectionUsers)
          .doc(userId)
          .collection(AppConstants.firestoreCollectionGroups)
          .doc(groupId)
          .set({
        'name': groupName,
        'device_ids': deviceIds,
        'device_names': deviceNames,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _logger.i('Group saved: $groupName');
    } catch (e) {
      _logger.e('Failed to save group: $e');
    }
  }

  /// Load saved groups from Firestore.
  Future<List<Map<String, dynamic>>> loadGroups() async {
    if (!_initialized || userId == null) return [];
    try {
      final snapshot = await _firestore!
          .collection(AppConstants.firestoreCollectionUsers)
          .doc(userId)
          .collection(AppConstants.firestoreCollectionGroups)
          .orderBy('created_at', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      _logger.e('Failed to load groups: $e');
      return [];
    }
  }

  /// Delete a saved group.
  Future<void> deleteGroup(String groupId) async {
    if (!_initialized || userId == null) return;
    try {
      await _firestore!
          .collection(AppConstants.firestoreCollectionUsers)
          .doc(userId)
          .collection(AppConstants.firestoreCollectionGroups)
          .doc(groupId)
          .delete();
      _logger.i('Group deleted: $groupId');
    } catch (e) {
      _logger.e('Failed to delete group: $e');
    }
  }

  /// Save user preferences to Firestore.
  Future<void> savePreferences({
    required Map<String, dynamic> prefs,
  }) async {
    if (!_initialized || userId == null) return;
    try {
      await _firestore!
          .collection(AppConstants.firestoreCollectionUsers)
          .doc(userId)
          .set({
        'preferences': prefs,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logger.e('Failed to save preferences: $e');
    }
  }

  /// Load user preferences from Firestore.
  Future<Map<String, dynamic>> loadPreferences() async {
    if (!_initialized || userId == null) return {};
    try {
      final doc = await _firestore!
          .collection(AppConstants.firestoreCollectionUsers)
          .doc(userId)
          .get();

      return doc.data()?['preferences'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      _logger.e('Failed to load preferences: $e');
      return {};
    }
  }

  // ── Cleanup ──

  /// Dispose (not typically needed, but useful for testing).
  void dispose() {
    _initialized = false;
  }
}
