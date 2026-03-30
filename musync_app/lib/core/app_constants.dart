/// Application-wide constants for MusyncMIMO.
/// Centralizes all magic numbers and configuration values.
library;

class AppConstants {
  AppConstants._(); // Prevent instantiation

  // ── App Info ──────────────────────────────────────────
  static const String appVersion = '0.1.11';
  static const String appName = 'MusyncMIMO';

  // ── Network ───────────────────────────────────────────
  static const int defaultWebSocketPort = 7890;
  static const String webSocketPath = '/musync';
  static const String mdnsServiceType = '_musync._tcp';
  static const String mdnsMulticastAddress = '224.0.0.251';
  static const int mdnsPort = 5353;
  static const int deviceTtlSeconds = 60;

  // ── WebSocket Client ──────────────────────────────────
  static const int maxReconnectAttempts = 10;
  static const int initialReconnectDelayMs = 1000;
  static const int maxReconnectDelayMs = 30000;
  static const int maxSyncAttempts = 3;
  static const int clientHeartbeatIntervalMs = 2000;
  static const int connectionTimeoutMs = 5000;

  // ── WebSocket Server ──────────────────────────────────
  static const int serverHeartbeatIntervalMs = 5000;
  static const int serverHeartbeatTimeoutMs = 15000;

  // ── Clock Sync ────────────────────────────────────────
  static const int calibrationSampleDelayMs = 50;
  static const int autoCalibrationIntervalMs = 10000;
  static const int maxSampleHistory = 50;
  static const int samplesPerCalibration = 8;

  // ── File Transfer ─────────────────────────────────────
  static const int fileChunkSizeBytes = 64 * 1024; // 64KB
  static const int fileTransferTimeoutSeconds = 30;
  static const int interChunkDelayMs = 5;
  static const int interChunkDelayInterval = 5; // delay every N chunks

  // ── Audio ─────────────────────────────────────────────
  static const int positionUpdateIntervalMs = 200;
  static const int maxSlaves = 8;
  static const int skipPreviousRestartThresholdSeconds = 3;

  // ── Session ───────────────────────────────────────────
  static const int defaultPlayDelayMs = 3000;
  static const int resumeDelayMs = 1500;
  static const int prepareBroadcastDelayMs = 300;
  static const int fileTransferWaitDelayMs = 500;
  static const int fileWaitRetryCount = 10;
  static const int fileWaitRetryDelayMs = 500;
  static const int lateCompensationThresholdMs = 5000;
  static const int lateCompensationMaxCompensationMs = 30000;

  // ── Discovery ─────────────────────────────────────────
  static const int tcpScanBatchSize = 20;
  static const int probeTimeoutMs = 800;

  // ── Firebase ──────────────────────────────────────────
  static const String firestoreCollectionUsers = 'users';
  static const String firestoreCollectionGroups = 'groups';

  // ── Platform Channels ─────────────────────────────────
  static const String foregroundServiceChannel = 'com.musync.mimo/foreground';
}
