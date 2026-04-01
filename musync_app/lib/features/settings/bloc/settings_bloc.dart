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

class ApkTransferToDeviceRequested extends SettingsEvent {
  final DeviceInfo device;

  const ApkTransferToDeviceRequested(this.device);

  @override
  List<Object?> get props => [device];
}

class ApkUpdateConnectedDeviceRequested extends SettingsEvent {
  const ApkUpdateConnectedDeviceRequested();
}

class ApkTransferProgress extends SettingsEvent {
  final double progress;

  const ApkTransferProgress(this.progress);

  @override
  List<Object?> get props => [progress];
}

// ── State ──

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final String deviceName;
  final double defaultVolume;
  final int cacheSize;
  final bool isLoading;
  final String? errorMessage;
  final bool isApkTransferring;
  final double apkTransferProgress;
  final String? apkTransferStatus;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.deviceName = 'MusyncMIMO Device',
    this.defaultVolume = 1.0,
    this.cacheSize = 0,
    this.isLoading = true,
    this.errorMessage,
    this.isApkTransferring = false,
    this.apkTransferProgress = 0.0,
    this.apkTransferStatus,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? deviceName,
    double? defaultVolume,
    int? cacheSize,
    bool? isLoading,
    String? errorMessage,
    bool? isApkTransferring,
    double? apkTransferProgress,
    String? apkTransferStatus,
    bool clearError = false,
    bool clearApkStatus = false,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      deviceName: deviceName ?? this.deviceName,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      cacheSize: cacheSize ?? this.cacheSize,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isApkTransferring: isApkTransferring ?? this.isApkTransferring,
      apkTransferProgress: apkTransferProgress ?? this.apkTransferProgress,
      apkTransferStatus: clearApkStatus ? null : (apkTransferStatus ?? this.apkTransferStatus),
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
        isApkTransferring,
        apkTransferProgress,
        apkTransferStatus,
      ];
}

// ── BLoC ──

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SharedPreferences _prefs;
  final SessionManager _sessionManager;
  final FirebaseService _firebase;
  final Logger _logger;

  SettingsBloc({
    required SharedPreferences prefs,
    required SessionManager sessionManager,
    FirebaseService? firebase,
    Logger? logger,
  })  : _prefs = prefs,
        _sessionManager = sessionManager,
        _firebase = firebase ?? FirebaseService(),
        _logger = logger ?? Logger(),
        super(const SettingsState()) {
    on<LoadSettings>(_onLoadSettings);
    on<ThemeChanged>(_onThemeChanged);
    on<DeviceNameChanged>(_onDeviceNameChanged);
    on<DefaultVolumeChanged>(_onDefaultVolumeChanged);
    on<CacheCleared>(_onCacheCleared);
    on<ApkTransferToDeviceRequested>(_onApkTransferToDevice);
    on<ApkUpdateConnectedDeviceRequested>(_onApkUpdateConnectedDevice);
    on<ApkTransferProgress>(_onApkTransferProgress);
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

      emit(SettingsState(
        themeMode: themeMode,
        deviceName: deviceName,
        defaultVolume: defaultVolume,
        cacheSize: cacheSize,
        isLoading: false,
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
    } catch (_) {
      return 0;
    }
  }

  Future<void> _onApkTransferToDevice(
    ApkTransferToDeviceRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isApkTransferring: true, apkTransferProgress: 0.0, apkTransferStatus: 'Envoi en cours...'));

    try {
      // Get APK path
      final apkPath = await _getApkPath();
      if (apkPath == null) {
        emit(state.copyWith(
          isApkTransferring: false,
          errorMessage: 'Impossible de trouver le fichier APK',
          clearApkStatus: true,
        ));
        return;
      }

      // Send APK offer to device
      final apkFile = File(apkPath);
      final fileSize = await apkFile.length();
      final offerMsg = ProtocolMessage.apkTransferOffer(
        version: AppConstants.appVersion,
        fileSizeBytes: fileSize,
      );

      // If device is connected as slave, send directly
      if (_sessionManager.role == DeviceRole.host) {
        await _sessionManager.sendToSlave(event.device.id, offerMsg);
        emit(state.copyWith(
          isApkTransferring: false,
          apkTransferStatus: 'Offre envoyée à ${event.device.name}',
        ));
      } else {
        emit(state.copyWith(
          isApkTransferring: false,
          errorMessage: 'Vous devez être hôte pour envoyer l\'APK',
          clearApkStatus: true,
        ));
      }
    } catch (e, stack) {
      _logger.e('Failed to send APK transfer offer: $e');
      _firebase.recordError(e, stack, reason: 'apkTransferOffer');
      emit(state.copyWith(
        isApkTransferring: false,
        errorMessage: 'Erreur lors de l\'envoi de l\'APK: $e',
        clearApkStatus: true,
      ));
    }
  }

  Future<void> _onApkUpdateConnectedDevice(
    ApkUpdateConnectedDeviceRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isApkTransferring: true, apkTransferProgress: 0.0, apkTransferStatus: 'Vérification des versions...'));

    try {
      final session = _sessionManager.currentSession;
      if (session == null || _sessionManager.role != DeviceRole.host) {
        emit(state.copyWith(
          isApkTransferring: false,
          errorMessage: 'Vous devez être hôte dans une session',
          clearApkStatus: true,
        ));
        return;
      }

      // Get APK info
      final apkPath = await _getApkPath();
      if (apkPath == null) {
        emit(state.copyWith(
          isApkTransferring: false,
          errorMessage: 'Impossible de trouver le fichier APK',
          clearApkStatus: true,
        ));
        return;
      }

      final apkFile = File(apkPath);
      final fileSize = await apkFile.length();

      // Send offer to all connected slaves
      final offerMsg = ProtocolMessage.apkTransferOffer(
        version: AppConstants.appVersion,
        fileSizeBytes: fileSize,
      );

      await _sessionManager.broadcast(offerMsg);

      emit(state.copyWith(
        isApkTransferring: false,
        apkTransferStatus: 'Offre de mise à jour envoyée (${session.slaves.length} appareils)',
      ));
    } catch (e, stack) {
      _logger.e('Failed to send APK update offer: $e');
      _firebase.recordError(e, stack, reason: 'apkUpdateOffer');
      emit(state.copyWith(
        isApkTransferring: false,
        errorMessage: 'Erreur lors de l\'envoi de la mise à jour: $e',
        clearApkStatus: true,
      ));
    }
  }

  void _onApkTransferProgress(
    ApkTransferProgress event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(
      apkTransferProgress: event.progress,
      apkTransferStatus: 'Envoi: ${(event.progress * 100).round()}%',
    ));
  }

  /// Get the path of the current APK file.
  Future<String?> _getApkPath() async {
    try {
      if (!Platform.isAndroid) {
        _logger.w('APK transfer only supported on Android');
        return null;
      }

      // On Android, get the APK path from the package info
      final appDir = await getApplicationSupportDirectory();
      final apkDir = Directory('${appDir.path}/apk_cache');
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }

      // Check if we have a cached APK
      final cachedApk = File('${apkDir.path}/musync-${AppConstants.appVersion}.apk');
      if (await cachedApk.exists()) {
        return cachedApk.path;
      }

      // APK not cached - need to build or copy from assets
      // For now, return null - in production, this would trigger a build
      _logger.w('APK not found in cache. Build APK first with: flutter build apk');
      return null;
    } catch (e) {
      _logger.e('Failed to get APK path: $e');
      return null;
    }
  }
}
