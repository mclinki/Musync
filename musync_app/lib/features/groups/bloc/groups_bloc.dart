import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/models/group.dart';

// Events
abstract class GroupsEvent extends Equatable {
  const GroupsEvent();
  @override
  List<Object?> get props => [];
}

class LoadGroups extends GroupsEvent {
  const LoadGroups();
}
class CreateGroup extends GroupsEvent {
  final String name;
  final String hostDeviceId;
  final String hostDeviceName;
  const CreateGroup({required this.name, required this.hostDeviceId, required this.hostDeviceName});
  @override
  List<Object?> get props => [name, hostDeviceId, hostDeviceName];
}
class DeleteGroup extends GroupsEvent {
  final String groupId;
  const DeleteGroup(this.groupId);
  @override
  List<Object?> get props => [groupId];
}
class RenameGroup extends GroupsEvent {
  final String groupId;
  final String newName;
  const RenameGroup({required this.groupId, required this.newName});
  @override
  List<Object?> get props => [groupId, newName];
}

// State
class GroupsState extends Equatable {
  final List<Group> groups;
  final bool isLoading;
  final String? errorMessage;

  const GroupsState({this.groups = const [], this.isLoading = false, this.errorMessage});

  GroupsState copyWith({List<Group>? groups, bool? isLoading, String? errorMessage}) {
    return GroupsState(
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [groups, isLoading, errorMessage];
}

// BLoC
class GroupsBloc extends Bloc<GroupsEvent, GroupsState> {
  final FirebaseService _firebase;
  final Logger _logger;

  GroupsBloc({FirebaseService? firebase, Logger? logger})
      : _firebase = firebase ?? FirebaseService(),
        _logger = logger ?? Logger(),
        super(const GroupsState()) {
    on<LoadGroups>(_onLoadGroups);
    on<CreateGroup>(_onCreateGroup);
    on<DeleteGroup>(_onDeleteGroup);
    on<RenameGroup>(_onRenameGroup);
  }

  Future<void> _onLoadGroups(LoadGroups event, Emitter<GroupsState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final rawGroups = await _firebase.loadGroups();
      final groups = rawGroups.map((json) => Group.fromJson(json)).toList();
      emit(state.copyWith(groups: groups, isLoading: false));
      _logger.i('Loaded ${groups.length} groups');
    } catch (e) {
      _logger.w('Failed to load groups: $e');
      emit(state.copyWith(isLoading: false, groups: []));
    }
  }

  Future<void> _onCreateGroup(CreateGroup event, Emitter<GroupsState> emit) async {
    try {
      final group = Group.create(
        name: event.name,
        hostDeviceId: event.hostDeviceId,
        hostDeviceName: event.hostDeviceName,
      );
      await _firebase.saveGroup(
        groupId: group.id,
        groupName: group.name,
        deviceIds: group.memberDeviceIds,
        deviceNames: [group.hostDeviceName],
      );
      add(const LoadGroups());
      _logger.i('Created group: ${group.name}');
    } catch (e) {
      _logger.e('Failed to create group: $e');
      emit(state.copyWith(errorMessage: 'Impossible de créer le groupe: $e'));
    }
  }

  Future<void> _onDeleteGroup(DeleteGroup event, Emitter<GroupsState> emit) async {
    try {
      await _firebase.deleteGroup(event.groupId);
      add(const LoadGroups());
      _logger.i('Deleted group: ${event.groupId}');
    } catch (e) {
      _logger.e('Failed to delete group: $e');
      emit(state.copyWith(errorMessage: 'Impossible de supprimer le groupe: $e'));
    }
  }

  Future<void> _onRenameGroup(RenameGroup event, Emitter<GroupsState> emit) async {
    try {
      final group = state.groups.firstWhere((g) => g.id == event.groupId);
      final updated = group.copyWith(name: event.newName, lastUsed: DateTime.now());
      await _firebase.saveGroup(
        groupId: updated.id,
        groupName: updated.name,
        deviceIds: updated.memberDeviceIds,
        deviceNames: [updated.hostDeviceName],
      );
      add(const LoadGroups());
      _logger.i('Renamed group to: ${event.newName}');
    } catch (e) {
      _logger.e('Failed to rename group: $e');
      emit(state.copyWith(errorMessage: 'Impossible de renommer le groupe: $e'));
    }
  }
}
