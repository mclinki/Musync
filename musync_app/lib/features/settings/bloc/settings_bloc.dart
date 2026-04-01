import 'dart:async';
import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
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

// ── State ──

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final String deviceName;
  final double defaultVolume;
  final int cacheSize;
  final bool isLoading;
  final String? errorMessage;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.deviceName = 'MusyncMIMO Device',
    this.defaultVolume = 1.0,
    this.cacheSize = 0,
    this.isLoading = true,
    this.errorMessage,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? deviceName,
    double? defaultVolume,
    int? cacheSize,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      deviceName: deviceName ?? this.deviceName,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      cacheSize: cacheSize ?? this.cacheSize,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
        _firebase = firebase ?? _firebase,
        _logger = logger ?? Logger(),
        super(const SettingsState()) {
    on<LoadSettings>(_onLoadSettings);
    on<ThemeChanged>(_onThemeChanged);
    on<DeviceNameChanged>(_onDeviceNameChanged);
    on<DefaultVolumeChanged>(_onDefaultVolumeChanged);
    on<CacheCleared>(_onCacheCleared);
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
}
