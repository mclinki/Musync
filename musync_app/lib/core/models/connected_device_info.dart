import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'device_info.dart';

/// Quality of clock synchronization between host and slave.
enum SyncQuality {
  unknown,
  excellent,
  good,
  acceptable,
  degraded;

  String get label {
    switch (this) {
      case SyncQuality.unknown:
        return 'Inconnu';
      case SyncQuality.excellent:
        return 'Excellent';
      case SyncQuality.good:
        return 'Bon';
      case SyncQuality.acceptable:
        return 'Acceptable';
      case SyncQuality.degraded:
        return 'Dégradé';
    }
  }

  Color get color {
    switch (this) {
      case SyncQuality.unknown:
        return Colors.grey;
      case SyncQuality.excellent:
        return Colors.green;
      case SyncQuality.good:
        return Colors.lightGreen;
      case SyncQuality.acceptable:
        return Colors.orange;
      case SyncQuality.degraded:
        return Colors.red;
    }
  }
}

/// Represents a connected slave device with real-time sync info.
/// Used by the host dashboard to display device status.
class ConnectedDeviceInfo extends Equatable {
  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;
  final String ip;
  final double clockOffsetMs;
  final bool isSynced;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;

  const ConnectedDeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ip,
    required this.clockOffsetMs,
    required this.isSynced,
    required this.connectedAt,
    required this.lastHeartbeat,
  });

  /// How long this device has been connected.
  Duration get uptime => DateTime.now().difference(connectedAt);

  /// Time since last heartbeat (indicates connection health).
  Duration get timeSinceLastHeartbeat =>
      DateTime.now().difference(lastHeartbeat);

  /// Whether the connection is healthy (heartbeat within 15s).
  bool get isHealthy => timeSinceLastHeartbeat.inSeconds < 15;

  /// Sync quality based on clock offset.
  SyncQuality get syncQuality {
    if (!isSynced) return SyncQuality.unknown;
    final absOffset = clockOffsetMs.abs();
    if (absOffset < 5) return SyncQuality.excellent;
    if (absOffset < 15) return SyncQuality.good;
    if (absOffset < 30) return SyncQuality.acceptable;
    return SyncQuality.degraded;
  }

  @override
  List<Object?> get props => [
        deviceId,
        deviceName,
        deviceType,
        ip,
        clockOffsetMs,
        isSynced,
        connectedAt,
        lastHeartbeat,
      ];
}
