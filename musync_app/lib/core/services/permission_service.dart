import 'dart:io';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Handles runtime permission requests for Android 13+ and iOS.
///
/// Required permissions:
/// - NEARBY_WIFI_DEVICES: Android 13+ for mDNS/network discovery
/// - READ_MEDIA_AUDIO: Android 13+ for audio file access
/// - ACCESS_FINE_LOCATION: Some Android versions require this for Wi-Fi state
class PermissionService {
  final Logger _logger;

  PermissionService({Logger? logger}) : _logger = logger ?? Logger();

  /// Request all permissions required for MusyncMIMO to function.
  /// Returns true if all critical permissions are granted.
  Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _logger.i('Not a mobile platform, skipping permissions');
      return true;
    }

    _logger.i('Requesting permissions...');
    final results = <ph.Permission, ph.PermissionStatus>{};

    // Collect permissions needed
    final permissions = <ph.Permission>[
      // Network discovery (Android 13+)
      ph.Permission.nearbyWifiDevices,
      // Audio file access
      if (Platform.isAndroid) ph.Permission.audio,
      // Location (required for Wi-Fi state on some Android versions)
      ph.Permission.locationWhenInUse,
    ];

    // Request all at once
    for (final permission in permissions) {
      final status = await permission.request();
      results[permission] = status;
      _logger.d('${permission.toString()}: ${status.toString()}');
    }

    // Check critical permissions
    final allGranted = results.values.every(
      (status) =>
          status == ph.PermissionStatus.granted ||
          status == ph.PermissionStatus.limited,
    );

    if (!allGranted) {
      _logger.w('Some permissions were denied:');
      for (final entry in results.entries) {
        if (entry.value != ph.PermissionStatus.granted &&
            entry.value != ph.PermissionStatus.limited) {
          _logger.w('  - ${entry.key}: ${entry.value}');
        }
      }
    } else {
      _logger.i('All permissions granted');
    }

    return allGranted;
  }

  /// Check if nearby Wi-Fi devices permission is granted (Android 13+).
  Future<bool> hasNearbyWifiPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await ph.Permission.nearbyWifiDevices.status;
    return status == ph.PermissionStatus.granted ||
        status == ph.PermissionStatus.limited;
  }

  /// Check if audio file permission is granted.
  Future<bool> hasAudioPermission() async {
    if (Platform.isAndroid) {
      final status = await ph.Permission.audio.status;
      return status == ph.PermissionStatus.granted ||
          status == ph.PermissionStatus.limited;
    }
    return true;
  }

  /// Request only the nearby Wi-Fi devices permission.
  Future<bool> requestNearbyWifiPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await ph.Permission.nearbyWifiDevices.request();
    return status == ph.PermissionStatus.granted ||
        status == ph.PermissionStatus.limited;
  }

  /// Request only the audio permission.
  Future<bool> requestAudioPermission() async {
    if (Platform.isAndroid) {
      final status = await ph.Permission.audio.request();
      return status == ph.PermissionStatus.granted ||
          status == ph.PermissionStatus.limited;
    }
    return true;
  }

  /// Open app settings if permissions are permanently denied.
  Future<void> openAppSettingsPage() async {
    await ph.openAppSettings();
  }
}
