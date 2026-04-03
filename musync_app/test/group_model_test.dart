import 'package:flutter_test/flutter_test.dart';
import 'package:musync_mimo/core/models/group.dart';

void main() {
  group('Group create', () {
    test('creates group with generated id', () {
      final group = Group.create(
        name: 'Test Group',
        hostDeviceId: 'device-1',
        hostDeviceName: 'Device One',
      );

      expect(group.id, isNotEmpty);
      expect(group.name, 'Test Group');
      expect(group.hostDeviceId, 'device-1');
      expect(group.hostDeviceName, 'Device One');
      expect(group.memberDeviceIds, isEmpty);
    });

    test('sets createdAt and lastUsed to now', () {
      final before = DateTime.now();
      final group = Group.create(
        name: 'Test',
        hostDeviceId: 'dev-1',
        hostDeviceName: 'Dev',
      );
      final after = DateTime.now();

      expect(group.createdAt.isBefore(after) || group.createdAt.isAtSameMomentAs(after), isTrue);
      expect(group.createdAt.isAfter(before) || group.createdAt.isAtSameMomentAs(before), isTrue);
      expect(group.lastUsed, isNotNull);
    });
  });

  group('Group copyWith', () {
    late Group group;

    setUp(() {
      group = Group(
        id: 'g-1',
        name: 'Original',
        hostDeviceId: 'dev-1',
        hostDeviceName: 'Device',
        createdAt: DateTime(2024, 1, 1),
        memberDeviceIds: ['dev-1', 'dev-2'],
      );
    });

    test('updates name', () {
      final updated = group.copyWith(name: 'Renamed');
      expect(updated.name, 'Renamed');
      expect(updated.id, 'g-1');
    });

    test('updates lastUsed', () {
      final newDate = DateTime(2025, 6, 15);
      final updated = group.copyWith(lastUsed: newDate);
      expect(updated.lastUsed, newDate);
    });

    test('updates memberDeviceIds', () {
      final updated = group.copyWith(memberDeviceIds: ['dev-1', 'dev-3', 'dev-4']);
      expect(updated.memberDeviceIds, ['dev-1', 'dev-3', 'dev-4']);
    });

    test('preserves unspecified fields', () {
      final updated = group.copyWith(name: 'New Name');
      expect(updated.id, 'g-1');
      expect(updated.hostDeviceId, 'dev-1');
      expect(updated.hostDeviceName, 'Device');
      expect(updated.createdAt, DateTime(2024, 1, 1));
      expect(updated.memberDeviceIds, ['dev-1', 'dev-2']);
    });

    test('returns identical group when no args', () {
      final updated = group.copyWith();
      expect(updated.id, group.id);
      expect(updated.name, group.name);
      expect(updated.hostDeviceId, group.hostDeviceId);
      expect(updated.createdAt, group.createdAt);
      expect(updated.memberDeviceIds, group.memberDeviceIds);
    });
  });

  group('Group toJson / fromJson', () {
    test('serializes all fields', () {
      final group = Group(
        id: 'g-123',
        name: 'My Group',
        hostDeviceId: 'host-1',
        hostDeviceName: 'Host Device',
        createdAt: DateTime(2024, 3, 15, 10, 30, 0),
        lastUsed: DateTime(2024, 4, 1, 14, 0, 0),
        memberDeviceIds: ['host-1', 'slave-1', 'slave-2'],
      );

      final json = group.toJson();
      expect(json['id'], 'g-123');
      expect(json['name'], 'My Group');
      expect(json['host_device_id'], 'host-1');
      expect(json['host_device_name'], 'Host Device');
      expect(json['created_at'], '2024-03-15T10:30:00.000');
      expect(json['last_used'], '2024-04-01T14:00:00.000');
      expect(json['member_device_ids'], ['host-1', 'slave-1', 'slave-2']);
    });

    test('serializes null lastUsed', () {
      final group = Group(
        id: 'g-1',
        name: 'Test',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: DateTime(2024, 1, 1),
        lastUsed: null,
      );

      final json = group.toJson();
      expect(json['last_used'], isNull);
    });

    test('round-trips through json', () {
      final original = Group(
        id: 'g-abc',
        name: 'Round Trip',
        hostDeviceId: 'dev-x',
        hostDeviceName: 'Device X',
        createdAt: DateTime(2024, 7, 20, 8, 15, 30),
        lastUsed: DateTime(2024, 8, 5, 16, 45, 0),
        memberDeviceIds: ['dev-x', 'dev-y'],
      );

      final json = original.toJson();
      final restored = Group.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.hostDeviceId, original.hostDeviceId);
      expect(restored.hostDeviceName, original.hostDeviceName);
      expect(restored.createdAt, original.createdAt);
      expect(restored.lastUsed, original.lastUsed);
      expect(restored.memberDeviceIds, original.memberDeviceIds);
    });

    test('deserializes with missing fields uses defaults', () {
      final json = <String, dynamic>{
        'id': 'g-minimal',
        'created_at': '2024-01-01T00:00:00.000',
      };

      final group = Group.fromJson(json);
      expect(group.id, 'g-minimal');
      expect(group.name, 'Groupe sans nom');
      expect(group.hostDeviceId, '');
      expect(group.hostDeviceName, '');
      expect(group.lastUsed, isNull);
      expect(group.memberDeviceIds, isEmpty);
    });

    test('deserializes with null last_used', () {
      final json = <String, dynamic>{
        'id': 'g-1',
        'name': 'Test',
        'host_device_id': 'd1',
        'host_device_name': 'D1',
        'created_at': '2024-01-01T00:00:00.000',
        'last_used': null,
        'member_device_ids': [],
      };

      final group = Group.fromJson(json);
      expect(group.lastUsed, isNull);
    });
  });

  group('Group Equatable', () {
    test('equal groups have same props', () {
      final date = DateTime(2024, 5, 10);
      final a = Group(
        id: 'g-1',
        name: 'Same',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: date,
        lastUsed: date,
        memberDeviceIds: ['d1'],
      );
      final b = Group(
        id: 'g-1',
        name: 'Same',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: date,
        lastUsed: date,
        memberDeviceIds: ['d1'],
      );

      expect(a, equals(b));
    });

    test('different ids means not equal', () {
      final date = DateTime(2024, 5, 10);
      final a = Group(
        id: 'g-1',
        name: 'Same',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: date,
      );
      final b = Group(
        id: 'g-2',
        name: 'Same',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: date,
      );

      expect(a, isNot(equals(b)));
    });
  });
}
