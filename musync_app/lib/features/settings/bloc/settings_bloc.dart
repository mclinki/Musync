import 'dart:async';
import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/core.dart';

// ── Events ──

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettings extends SettingsEvent {
  const LoadSettings();
}

class ThemeChanged extends SettingsEvent {
  final ThemeMode themeMode;

  const ThemeChanged(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

class DeviceNameChanged extends SettingsEvent {
  final String deviceName;

  const DeviceNameChanged(this.deviceName);

  @override
  List<Object?> get props => [deviceName];
}

class DefaultVolumeChanged extends SettingsEvent {
  final double volume;

  const DefaultVolumeChanged(this.volume);

  @override
  List<Object?> get props => [volume];
}

class CacheCleared extends SettingsEvent {
  const CacheCleared();
}

/// Start the HTTP server to share the APK on the local network.
class ApkShareStartRequested extends SettingsEvent {
  const ApkShareStartRequested();
}

/// Stop the HTTP APK share server.
class ApkShareStopRequested extends SettingsEvent {
  const ApkShareStopRequested();
}

/// Check GitHub Releases for a newer version.
class UpdateCheckRequested extends SettingsEvent {
  const UpdateCheckRequested();
}

/// Download the available update APK.
class UpdateDownloadRequested extends SettingsEvent {
  const UpdateDownloadRequested();
}

class JoinNotificationToggled extends SettingsEvent {
  final bool enabled;

  const JoinNotificationToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class PlayDelayChanged extends SettingsEvent {
  final int delayMs;

  const PlayDelayChanged(this.delayMs);

  @override
  List<Object?> get props => [delayMs];
}

class AutoRejoinToggled extends SettingsEvent {
  final bool enabled;

  const AutoRejoinToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

// ── State ──

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final String deviceName;
  final double defaultVolume;
  final int cacheSize;
  final bool isLoading;
  final String? errorMessage;

  // APK share
  final bool isApkShareRunning;
  final String? apkShareUrl;
  final int apkSharePort;

  // Update
  final bool isCheckingUpdate;
  final bool isDownloadingUpdate;
  final UpdateInfo? updateInfo;
  final double downloadProgress;
  final String? downloadedApkPath;

  // Notifications
  final bool joinNotificationEnabled;

  // Advanced
  final int playDelayMs;
  final bool autoRejoinLastSession;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.deviceName = 'MusyncMIMO Device',
    this.defaultVolume = 1.0,
    this.cacheSize = 0,
    this.isLoading = true,
    this.errorMessage,
    this.isApkShareRunning = false,
    this.apkShareUrl,
    this.apkSharePort = 8080,
    this.isCheckingUpdate = false,
    this.isDownloadingUpdate = false,
    this.updateInfo,
    this.downloadProgress = 0.0,
    this.downloadedApkPath,
    this.joinNotificationEnabled = true,
    this.playDelayMs = 5000,
    this.autoRejoinLastSession = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? deviceName,
    double? defaultVolume,
    int? cacheSize,
    bool? isLoading,
    String? errorMessage,
    bool? isApkShareRunning,
    String? apkShareUrl,
    int? apkSharePort,
    bool clearError = false,
    bool clearShareUrl = false,
    bool? isCheckingUpdate,
    bool? isDownloadingUpdate,
    UpdateInfo? updateInfo,
    double? downloadProgress,
    String? downloadedApkPath,
    bool clearUpdateInfo = false,
    bool clearDownloadedPath = false,
    bool? joinNotificationEnabled,
    int? playDelayMs,
    bool? autoRejoinLastSession,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      deviceName: deviceName ?? this.deviceName,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      cacheSize: cacheSize ?? this.cacheSize,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isApkShareRunning: isApkShareRunning ?? this.isApkShareRunning,
      apkShareUrl: clearShareUrl ? null : (apkShareUrl ?? this.apkShareUrl),
      apkSharePort: apkSharePort ?? this.apkSharePort,
      isCheckingUpdate: isCheckingUpdate ?? this.isCheckingUpdate,
      isDownloadingUpdate: isDownloadingUpdate ?? this.isDownloadingUpdate,
      updateInfo: clearUpdateInfo ? null : (updateInfo ?? this.updateInfo),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedApkPath: clearDownloadedPath ? null : (downloadedApkPath ?? this.downloadedApkPath),
      joinNotificationEnabled: joinNotificationEnabled ?? this.joinNotificationEnabled,
      playDelayMs: playDelayMs ?? this.playDelayMs,
      autoRejoinLastSession: autoRejoinLastSession ?? this.autoRejoinLastSession,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        deviceName,
        defaultVolume,
        cacheSize,
        isLoading,
        errorMessage,
        isApkShareRunning,
        apkShareUrl,
        apkSharePort,
        isCheckingUpdate,
        isDownloadingUpdate,
        updateInfo,
        downloadProgress,
        downloadedApkPath,
        joinNotificationEnabled,
        playDelayMs,
        autoRejoinLastSession,
      ];
}

// ── BLoC ──

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SharedPreferences _prefs;
  final SessionManager _sessionManager;
  final FirebaseService _firebase;
  final ApkShareService _apkShare;
  final UpdateService _update;
  final Logger _logger;

  SettingsBloc({
    required SharedPreferences prefs,
    required SessionManager sessionManager,
    FirebaseService? firebase,
    ApkShareService? apkShare,
    UpdateService? update,
    Logger? logger,
  })  : _prefs = prefs,
        _sessionManager = sessionManager,
        _firebase = firebase ?? FirebaseService(),
        _apkShare = apkShare ?? ApkShareService(),
        _update = update ?? UpdateService(),
        _logger = logger ?? Logger(),
        super(const SettingsState()) {
    on<LoadSettings>(_onLoadSettings);
    on<ThemeChanged>(_onThemeChanged);
    on<DeviceNameChanged>(_onDeviceNameChanged);
    on<DefaultVolumeChanged>(_onDefaultVolumeChanged);
    on<CacheCleared>(_onCacheCleared);
    on<ApkShareStartRequested>(_onApkShareStart);
    on<ApkShareStopRequested>(_onApkShareStop);
    on<UpdateCheckRequested>(_onUpdateCheck);
    on<UpdateDownloadRequested>(_onUpdateDownload);
    on<JoinNotificationToggled>(_onJoinNotificationToggled);
    on<PlayDelayChanged>(_onPlayDelayChanged);
    on<AutoRejoinToggled>(_onAutoRejoinToggled);
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == _prefs.getString('theme_mode'),
        orElse: () => ThemeMode.system,
      );
      final defaultVolume = _prefs.getDouble('default_volume') ?? 1.0;
      final deviceName =
          _prefs.getString('device_name') ?? 'MusyncMIMO Device';
      final cacheSize = await _calculateCacheSize();
      final joinNotificationEnabled = _prefs.getBool('join_notification_enabled') ?? true;
      final playDelayMs = _prefs.getInt('play_delay_ms') ?? 5000;
      final autoRejoinLastSession = _prefs.getBool('auto_rejoin_last_session') ?? false;

      emit(SettingsState(
        themeMode: themeMode,
        deviceName: deviceName,
        defaultVolume: defaultVolume,
        cacheSize: cacheSize,
        isLoading: false,
        isApkShareRunning: _apkShare.isRunning,
        joinNotificationEnabled: joinNotificationEnabled,
        playDelayMs: playDelayMs,
        autoRejoinLastSession: autoRejoinLastSession,
      ));
    } catch (e, stack) {
      _logger.e('Failed to load settings: $e');
      _firebase.recordError(e, stack, reason: 'loadSettings');
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Erreur lors du chargement des paramètres: $e',
      ));
    }
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _prefs.setString('theme_mode', event.themeMode.name);
      emit(state.copyWith(themeMode: event.themeMode, clearError: true));
    } catch (e, stack) {
      _logger.e('Failed to save theme: $e');
      _firebase.recordError(e, stack, reason: 'saveTheme');
      emit(state.copyWith(
        errorMessage: 'Erreur lors de la sauvegarde du thème: $e',
      ));
    }
  }

  Future<void> _onDeviceNameChanged(
    DeviceNameChanged event,
    Emitter<SettingsState> emit,
  ) async {
    await _prefs.setString('device_name', event.deviceName);
    // BUG-6 FIX: Propagate name change to session manager (discovery + local device)
    _sessionManager.updateDeviceName(event.deviceName);
    emit(state.copyWith(deviceName: event.deviceName, clearError: true));
  }

  Future<void> _onDefaultVolumeChanged(
    DefaultVolumeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    await _prefs.setDouble('default_volume', event.volume);
    await _sessionManager.audioEngine.setVolume(event.volume);
    emit(state.copyWith(defaultVolume: event.volume, clearError: true));
  }

  Future<void> _onCacheCleared(
    CacheCleared event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _sessionManager.fileTransfer.cleanup();
      final cacheSize = await _calculateCacheSize();
      emit(state.copyWith(cacheSize: cacheSize, clearError: true));
    } catch (e, stack) {
      _logger.e('Failed to clear cache: $e');
      _firebase.recordError(e, stack, reason: 'clearCache');
      emit(state.copyWith(
        errorMessage: 'Erreur lors du nettoyage du cache: $e',
      ));
    }
  }

  Future<int> _calculateCacheSize() async {
    try {
      final transferDir = _sessionManager.fileTransfer.cachePath;
      if (transferDir == null) return 0;
      final dir = Directory(transferDir);
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      _logger.d('Failed to calculate transfer dir size: $e');
      return 0;
    }
  }

  /// Start the HTTP server to share the APK.
  Future<void> _onApkShareStart(
    ApkShareStartRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isApkShareRunning: true, clearShareUrl: true));

    try {
      // 1. Start the HTTP server
      final port = await _apkShare.start(port: state.apkSharePort);
      if (port == null) {
        emit(state.copyWith(
          isApkShareRunning: false,
          errorMessage: 'Impossible de démarrer le partage APK. Vérifiez que l\'APK est disponible.',
        ));
        return;
      }

      // 2. Resolve local IP (from session if available, otherwise discover it)
      String? localIp = _sessionManager.localIp;
      if (localIp == null) {
        // Not in a session — resolve IP directly
        try {
          final discovery = DeviceDiscovery(
            deviceId: 'temp',
            deviceName: 'temp',
          );
          localIp = await discovery.getLocalIp();
          await discovery.dispose();
        } catch (e) {
          _logger.w('Failed to resolve IP via DeviceDiscovery: $e');
        }
      }

      if (localIp == null) {
        // BUG-9 FIX: Try fallback method to get local IP
        try {
          final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
          for (final interface in interfaces) {
            for (final addr in interface.addresses) {
              if (!addr.isLoopback) {
                localIp = addr.address;
                break;
              }
            }
            if (localIp != null) break;
          }
        } catch (e) {
          _logger.w('Failed to resolve IP via NetworkInterface: $e');
        }
      }

      if (localIp == null) {
        emit(state.copyWith(
          isApkShareRunning: false,
          errorMessage: 'Impossible de résoudre l\'adresse IP. Vérifiez votre connexion Wi-Fi.',
        ));
        await _apkShare.stop();
        return;
      }

      // 3. Build the share URL
      final shareUrl = 'http://$localIp:$port/apk';

      _logger.i('APK share started: $shareUrl');
      emit(state.copyWith(
        isApkShareRunning: true,
        apkShareUrl: shareUrl,
        apkSharePort: port,
      ));
    } catch (e, stack) {
      _logger.e('Failed to start APK share: $e');
      _firebase.recordError(e, stack, reason: 'apkShareStart');
      emit(state.copyWith(
        isApkShareRunning: false,
        errorMessage: 'Erreur lors du démarrage du partage: $e',
      ));
    }
  }

  /// Stop the HTTP APK share server.
  Future<void> _onApkShareStop(
    ApkShareStopRequested event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _apkShare.stop();
      _logger.i('APK share stopped');
      emit(state.copyWith(isApkShareRunning: false, clearShareUrl: true));
    } catch (e, stack) {
      _logger.e('Failed to stop APK share: $e');
      _firebase.recordError(e, stack, reason: 'apkShareStop');
      emit(state.copyWith(
        isApkShareRunning: false,
        clearShareUrl: true,
        errorMessage: 'Erreur lors de l\'arrêt du partage: $e',
      ));
    }
  }

  /// Check GitHub Releases for a newer version.
  Future<void> _onUpdateCheck(
    UpdateCheckRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isCheckingUpdate: true, clearError: true, clearUpdateInfo: true));
    try {
      final info = await _update.checkForUpdate(AppConstants.appVersion);
      if (info != null && info.isNewer) {
        _logger.i('Update available: ${info.latestVersion}');
        emit(state.copyWith(
          isCheckingUpdate: false,
          updateInfo: info,
        ));
      } else {
        _logger.i('No update available');
        emit(state.copyWith(
          isCheckingUpdate: false,
          errorMessage: 'Aucune mise à jour disponible. Vous avez déjà la dernière version.',
        ));
      }
    } catch (e, stack) {
      _logger.e('Update check failed: $e');
      _firebase.recordError(e, stack, reason: 'updateCheck');
      emit(state.copyWith(
        isCheckingUpdate: false,
        errorMessage: 'Erreur lors de la vérification: $e',
      ));
    }
  }

  /// Download the available update APK.
  Future<void> _onUpdateDownload(
    UpdateDownloadRequested event,
    Emitter<SettingsState> emit,
  ) async {
    final updateInfo = state.updateInfo;
    if (updateInfo == null) return;

    emit(state.copyWith(isDownloadingUpdate: true, downloadProgress: 0.0, clearError: true));
    try {
      final path = await _update.downloadUpdate(
        updateInfo,
        onProgress: (progress) {
          // Note: can't emit inside the callback safely, progress shown via state
        },
      );

      if (path != null) {
        _logger.i('Update downloaded: $path');
        emit(state.copyWith(
          isDownloadingUpdate: false,
          downloadProgress: 1.0,
          downloadedApkPath: path,
        ));
      } else {
        emit(state.copyWith(
          isDownloadingUpdate: false,
          errorMessage: 'Échec du téléchargement de la mise à jour.',
        ));
      }
    } catch (e, stack) {
      _logger.e('Update download failed: $e');
      _firebase.recordError(e, stack, reason: 'updateDownload');
      emit(state.copyWith(
        isDownloadingUpdate: false,
        errorMessage: 'Erreur lors du téléchargement: $e',
      ));
    }
  }

  Future<void> _onJoinNotificationToggled(
    JoinNotificationToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _prefs.setBool('join_notification_enabled', event.enabled);
    emit(state.copyWith(joinNotificationEnabled: event.enabled, clearError: true));
  }

  Future<void> _onPlayDelayChanged(
    PlayDelayChanged event,
    Emitter<SettingsState> emit,
  ) async {
    await _prefs.setInt('play_delay_ms', event.delayMs);
    emit(state.copyWith(playDelayMs: event.delayMs, clearError: true));
    _logger.i('Play delay changed: ${event.delayMs}ms');
  }

  Future<void> _onAutoRejoinToggled(
    AutoRejoinToggled event,
    Emitter<SettingsState> emit,
  ) async {
    await _prefs.setBool('auto_rejoin_last_session', event.enabled);
    emit(state.copyWith(autoRejoinLastSession: event.enabled, clearError: true));
    _logger.i('Auto-rejoin ${event.enabled ? "enabled" : "disabled"}');
  }
}
