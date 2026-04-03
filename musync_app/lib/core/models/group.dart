import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Group extends Equatable {
  final String id;
  final String name;
  final String hostDeviceId;
  final String hostDeviceName;
  final DateTime createdAt;
  final DateTime? lastUsed;
  final List<String> memberDeviceIds;

  const Group({
    required this.id,
    required this.name,
    required this.hostDeviceId,
    required this.hostDeviceName,
    required this.createdAt,
    this.lastUsed,
    this.memberDeviceIds = const [],
  });

  factory Group.create({required String name, required String hostDeviceId, required String hostDeviceName}) {
    return Group(
      id: const Uuid().v4(),
      name: name,
      hostDeviceId: hostDeviceId,
      hostDeviceName: hostDeviceName,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
  }

  Group copyWith({
    String? id,
    String? name,
    String? hostDeviceId,
    String? hostDeviceName,
    DateTime? createdAt,
    DateTime? lastUsed,
    List<String>? memberDeviceIds,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      hostDeviceName: hostDeviceName ?? this.hostDeviceName,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
      memberDeviceIds: memberDeviceIds ?? this.memberDeviceIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host_device_id': hostDeviceId,
    'host_device_name': hostDeviceName,
    'created_at': createdAt.toIso8601String(),
    'last_used': lastUsed?.toIso8601String(),
    'member_device_ids': memberDeviceIds,
  };

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Groupe sans nom',
      hostDeviceId: json['host_device_id'] as String? ?? '',
      hostDeviceName: json['host_device_name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used'] as String) : null,
      memberDeviceIds: (json['member_device_ids'] as List?)?.cast<String>() ?? [],
    );
  }

  @override
  List<Object?> get props => [id, name, hostDeviceId, hostDeviceName, createdAt, lastUsed, memberDeviceIds];
}
