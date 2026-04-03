import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musync_mimo/features/groups/bloc/groups_bloc.dart';
import 'package:musync_mimo/core/models/group.dart';
import 'package:musync_mimo/core/services/firebase_service.dart';

class MockFirebaseService extends Mock implements FirebaseService {}

void main() {
  late MockFirebaseService mockFirebase;

  setUp(() {
    mockFirebase = MockFirebaseService();
  });

  group('GroupsBloc', () {
    blocTest<GroupsBloc, GroupsState>(
      'LoadGroups emits loading then loaded state',
      setUp: () {
        when(() => mockFirebase.loadGroups()).thenAnswer((_) async => [
              {
                'id': 'g-1',
                'name': 'Group A',
                'host_device_id': 'dev-1',
                'host_device_name': 'Device 1',
                'created_at': '2024-01-01T00:00:00.000',
                'last_used': '2024-01-01T00:00:00.000',
                'member_device_ids': ['dev-1'],
              },
              {
                'id': 'g-2',
                'name': 'Group B',
                'host_device_id': 'dev-2',
                'host_device_name': 'Device 2',
                'created_at': '2024-02-01T00:00:00.000',
                'last_used': null,
                'member_device_ids': [],
              },
            ]);
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const LoadGroups()),
      expect: () => [
        isA<GroupsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<GroupsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.groups.length, 'group count', 2)
            .having((s) => s.groups[0].name, 'first group name', 'Group A')
            .having((s) => s.groups[1].name, 'second group name', 'Group B'),
      ],
    );

    blocTest<GroupsBloc, GroupsState>(
      'LoadGroups emits empty list on error',
      setUp: () {
        when(() => mockFirebase.loadGroups()).thenThrow(Exception('Network error'));
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const LoadGroups()),
      expect: () => [
        isA<GroupsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<GroupsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.groups, 'groups', isEmpty),
      ],
    );

    blocTest<GroupsBloc, GroupsState>(
      'CreateGroup saves group and reloads',
      setUp: () {
        when(() => mockFirebase.saveGroup(
              groupId: any(named: 'groupId'),
              groupName: any(named: 'groupName'),
              deviceIds: any(named: 'deviceIds'),
              deviceNames: any(named: 'deviceNames'),
            )).thenAnswer((_) async {});
        when(() => mockFirebase.loadGroups()).thenAnswer((_) async => [
              {
                'id': 'g-new',
                'name': 'New Group',
                'host_device_id': 'dev-1',
                'host_device_name': 'Device 1',
                'created_at': '2024-03-01T00:00:00.000',
                'last_used': '2024-03-01T00:00:00.000',
                'member_device_ids': [],
              },
            ]);
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const CreateGroup(
        name: 'New Group',
        hostDeviceId: 'dev-1',
        hostDeviceName: 'Device 1',
      )),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<GroupsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<GroupsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.groups.length, 'group count', 1),
      ],
      verify: (_) {
        verify(() => mockFirebase.saveGroup(
              groupId: any(named: 'groupId'),
              groupName: 'New Group',
              deviceIds: any(named: 'deviceIds'),
              deviceNames: ['Device 1'],
            )).called(1);
      },
    );

    blocTest<GroupsBloc, GroupsState>(
      'CreateGroup emits error on failure',
      setUp: () {
        when(() => mockFirebase.saveGroup(
              groupId: any(named: 'groupId'),
              groupName: any(named: 'groupName'),
              deviceIds: any(named: 'deviceIds'),
              deviceNames: any(named: 'deviceNames'),
            )).thenThrow(Exception('Firestore error'));
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const CreateGroup(
        name: 'Fail Group',
        hostDeviceId: 'dev-1',
        hostDeviceName: 'Device 1',
      )),
      expect: () => [
        isA<GroupsState>()
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<GroupsBloc, GroupsState>(
      'DeleteGroup removes group and reloads',
      setUp: () {
        when(() => mockFirebase.deleteGroup('g-1')).thenAnswer((_) async {});
        when(() => mockFirebase.loadGroups()).thenAnswer((_) async => []);
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const DeleteGroup('g-1')),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<GroupsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<GroupsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.groups, 'groups', isEmpty),
      ],
      verify: (_) {
        verify(() => mockFirebase.deleteGroup('g-1')).called(1);
      },
    );

    blocTest<GroupsBloc, GroupsState>(
      'DeleteGroup emits error on failure',
      setUp: () {
        when(() => mockFirebase.deleteGroup('g-1'))
            .thenThrow(Exception('Delete failed'));
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      act: (bloc) => bloc.add(const DeleteGroup('g-1')),
      expect: () => [
        isA<GroupsState>()
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<GroupsBloc, GroupsState>(
      'RenameGroup updates group and reloads',
      setUp: () {
        when(() => mockFirebase.saveGroup(
              groupId: any(named: 'groupId'),
              groupName: any(named: 'groupName'),
              deviceIds: any(named: 'deviceIds'),
              deviceNames: any(named: 'deviceNames'),
            )).thenAnswer((_) async {});
        when(() => mockFirebase.loadGroups()).thenAnswer((_) async => [
              {
                'id': 'g-1',
                'name': 'Renamed Group',
                'host_device_id': 'dev-1',
                'host_device_name': 'Device 1',
                'created_at': '2024-01-01T00:00:00.000',
                'last_used': '2024-06-01T00:00:00.000',
                'member_device_ids': ['dev-1'],
              },
            ]);
      },
      build: () => GroupsBloc(firebase: mockFirebase),
      seed: () => GroupsState(groups: [
        Group(
          id: 'g-1',
          name: 'Old Name',
          hostDeviceId: 'dev-1',
          hostDeviceName: 'Device 1',
          createdAt: DateTime(2024, 1, 1),
          memberDeviceIds: ['dev-1'],
        ),
      ]),
      act: (bloc) => bloc.add(const RenameGroup(
        groupId: 'g-1',
        newName: 'Renamed Group',
      )),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<GroupsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<GroupsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.groups[0].name, 'new name', 'Renamed Group'),
      ],
      verify: (_) {
        verify(() => mockFirebase.saveGroup(
              groupId: 'g-1',
              groupName: 'Renamed Group',
              deviceIds: ['dev-1'],
              deviceNames: ['Device 1'],
            )).called(1);
      },
    );

    blocTest<GroupsBloc, GroupsState>(
      'RenameGroup emits error when group not found',
      setUp: () {},
      build: () => GroupsBloc(firebase: mockFirebase),
      seed: () => const GroupsState(groups: []),
      act: (bloc) => bloc.add(const RenameGroup(
        groupId: 'g-nonexistent',
        newName: 'New Name',
      )),
      expect: () => [
        isA<GroupsState>()
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    test('initial state is empty and not loading', () {
      final bloc = GroupsBloc(firebase: mockFirebase);
      expect(bloc.state.groups, isEmpty);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.errorMessage, isNull);
    });
  });

  group('GroupsEvent Equatable', () {
    test('LoadGroups events are equal', () {
      expect(const LoadGroups(), const LoadGroups());
    });

    test('CreateGroup events equal when props match', () {
      const a = CreateGroup(name: 'A', hostDeviceId: '1', hostDeviceName: 'N');
      const b = CreateGroup(name: 'A', hostDeviceId: '1', hostDeviceName: 'N');
      expect(a, equals(b));
    });

    test('DeleteGroup events equal when groupId match', () {
      expect(const DeleteGroup('g-1'), const DeleteGroup('g-1'));
    });

    test('RenameGroup events equal when props match', () {
      const a = RenameGroup(groupId: 'g-1', newName: 'New');
      const b = RenameGroup(groupId: 'g-1', newName: 'New');
      expect(a, equals(b));
    });
  });

  group('GroupsState copyWith', () {
    test('updates groups', () {
      const state = GroupsState();
      final group = Group(
        id: 'g-1',
        name: 'Test',
        hostDeviceId: 'd1',
        hostDeviceName: 'D1',
        createdAt: DateTime(2024, 1, 1),
      );
      final updated = state.copyWith(groups: [group]);
      expect(updated.groups.length, 1);
      expect(updated.isLoading, false);
    });

    test('updates isLoading', () {
      const state = GroupsState();
      final updated = state.copyWith(isLoading: true);
      expect(updated.isLoading, true);
    });

    test('updates errorMessage', () {
      const state = GroupsState();
      final updated = state.copyWith(errorMessage: 'Error occurred');
      expect(updated.errorMessage, 'Error occurred');
    });

    test('clears errorMessage when not specified', () {
      final state = const GroupsState(errorMessage: 'Old error');
      final updated = state.copyWith(isLoading: false);
      expect(updated.errorMessage, isNull);
    });
  });
}
