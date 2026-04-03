import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/group.dart';
import '../bloc/groups_bloc.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GroupsBloc()..add(const LoadGroups()),
      child: const _GroupsView(),
    );
  }
}

class _GroupsView extends StatelessWidget {
  const _GroupsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groupes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: BlocBuilder<GroupsBloc, GroupsState>(
        builder: (context, state) {
          if (state.isLoading && state.groups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_off, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('Aucun groupe sauvegardé', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('Créez un groupe depuis l\'écran de découverte',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.groups.length,
            itemBuilder: (context, index) {
              final group = state.groups[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.group, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  title: Text(group.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hôte : ${group.hostDeviceName}'),
                      if (group.lastUsed != null)
                        Text('Dernière utilisation : ${_formatDate(group.lastUsed!)}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showRenameDialog(context, group),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _confirmDelete(context, group),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showCreateDialog(BuildContext context) {
    final bloc = context.read<GroupsBloc>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Créer un groupe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nom du groupe', hintText: 'ex: Soirée chez Marc'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                bloc.add(CreateGroup(
                  name: controller.text.trim(),
                  hostDeviceId: 'local',
                  hostDeviceName: 'Mon appareil',
                ));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, Group group) {
    final bloc = context.read<GroupsBloc>();
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renommer le groupe'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                bloc.add(RenameGroup(groupId: group.id, newName: controller.text.trim()));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Group group) {
    final bloc = context.read<GroupsBloc>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le groupe'),
        content: Text('Voulez-vous vraiment supprimer "${group.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              bloc.add(DeleteGroup(group.id));
              Navigator.pop(dialogContext);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
