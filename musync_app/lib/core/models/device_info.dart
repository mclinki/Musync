import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../app_constants.dart';

/// Represents a device in the MusyncMIMO network.
class DeviceInfo extends Equatable {
  final String id;
  final String name;
  final DeviceType type;
  final String ip;
  final int port;
  final String appVersion;
  final DeviceRole role;
  final DateTime discoveredAt;
  final bool isReachable;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.ip,
    required this.port,
    this.appVersion = AppConstants.appVersion,
    this.role = DeviceRole.any,
    required this.discoveredAt,
    this.isReachable = true,
  });

  factory DeviceInfo.fromMdns({
    required String name,
    required String ip,
    required int port,
    required Map<String, String> txtRecords,
  }) {
    return DeviceInfo(
      id: txtRecords['device_id'] ?? const Uuid().v4(),
      name: name,
      type: DeviceType.fromString(txtRecords['device_type'] ?? 'phone'),
      ip: ip,
      port: port,
      appVersion: txtRecords['app_version'] ?? AppConstants.appVersion,
      role: DeviceRole.fromString(txtRecords['role'] ?? 'any'),
      discoveredAt: DateTime.now(),
    );
  }

  DeviceInfo copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? ip,
    int? port,
    String? appVersion,
    DeviceRole? role,
    DateTime? discoveredAt,
    bool? isReachable,
  }) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      appVersion: appVersion ?? this.appVersion,
      role: role ?? this.role,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      isReachable: isReachable ?? this.isReachable,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'ip': ip,
        'port': port,
        'app_version': appVersion,
        'role': role.name,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      type: DeviceType.fromString(json['type'] as String? ?? 'phone'),
      ip: json['ip'] as String,
      port: json['port'] as int,
      appVersion: json['app_version'] as String? ?? AppConstants.appVersion,
      role: DeviceRole.fromString(json['role'] as String? ?? 'any'),
      discoveredAt: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, type, ip, port, role];
}

enum DeviceType {
  phone,
  tablet,
  speaker,
  tv,
  desktop,
  unknown;

  static DeviceType fromString(String value) {
    return DeviceType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DeviceType.unknown,
    );
  }

  String get icon {
    switch (this) {
      case DeviceType.phone:
        return '📱';
      case DeviceType.tablet:
        return '📱';
      case DeviceType.speaker:
        return '🔊';
      case DeviceType.tv:
        return '📺';
      case DeviceType.desktop:
        return '💻';
      case DeviceType.unknown:
        return '❓';
    }
  }
}

enum DeviceRole {
  none,   // Not in a session
  host,   // This device is the host (server)
  slave,  // This device is a slave (client)
  any;    // Can be either

  static DeviceRole fromString(String value) {
    return DeviceRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DeviceRole.any,
    );
  }
}
