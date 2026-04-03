import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/core.dart';
import '../bloc/player_bloc.dart';
import '../../settings/bloc/settings_bloc.dart';

/// Dashboard card showing connected devices and their sync status.
/// Only visible when this device is the host.
class HostDashboardCard extends StatelessWidget {
  const HostDashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GuestJoinNotifier(),
        BlocBuilder<PlayerBloc, PlayerState>(
          builder: (context, state) {
            final devices = state.connectedDevices;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    _buildHeader(context, devices.length, state.allGuestsReady),

                    const SizedBox(height: 12),

                    // Device list or empty state
                    if (devices.isEmpty)
                      _buildEmptyState(context)
                    else
                      ...devices.map((device) => _DeviceTile(device: device)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int deviceCount, bool allGuestsReady) {
    return Row(
      children: [
        Icon(
          Icons.devices,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'Appareils connectés',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.edit, size: 18),
          tooltip: 'Renommer la session',
          onPressed: () => _showRenameSessionDialog(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$deviceCount',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: allGuestsReady
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: allGuestsReady ? Colors.green : Colors.orange,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allGuestsReady ? Icons.check_circle : Icons.hourglass_empty,
                size: 14,
                color: allGuestsReady ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                allGuestsReady ? 'Tous prêts' : 'Chargement...',
                style: TextStyle(
                  color: allGuestsReady ? Colors.green : Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRenameSessionDialog(BuildContext context) {
    final sessionManager = context.read<SessionManager>();
    final currentName = sessionManager.currentSession?.name ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: currentName);
        return AlertDialog(
          title: const Text('Renommer la session'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Nom de la session',
              border: OutlineInputBorder(),
            ),
            maxLength: 30,
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final newName = controller.text.trim();
                controller.dispose();
                if (newName.isNotEmpty) {
                  try {
                    await sessionManager.renameSession(newName);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Session renommée'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erreur: $e')),
                      );
                    }
                  }
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            'Aucun appareil connecté',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

/// Listens to connected devices stream and shows a notification when a new guest joins.
class _GuestJoinNotifier extends StatefulWidget {
  @override
  State<_GuestJoinNotifier> createState() => _GuestJoinNotifierState();
}

class _GuestJoinNotifierState extends State<_GuestJoinNotifier> {
  Set<String> _knownDeviceIds = {};
  StreamSubscription<List<ConnectedDeviceInfo>>? _devicesSubscription;

  @override
  void initState() {
    super.initState();
    _listenToDevices();
  }

  void _listenToDevices() {
    final sessionManager = context.read<SessionManager>();
    _devicesSubscription = sessionManager.connectedDevicesStream.listen((devices) {
      if (!mounted) return;

      final currentIds = devices.map((d) => d.deviceId).toSet();
      final newDevices = currentIds.difference(_knownDeviceIds);

      if (newDevices.isNotEmpty && _knownDeviceIds.isNotEmpty) {
        final settingsBloc = context.read<SettingsBloc>();
        if (!mounted) return;
        final settingsState = settingsBloc.state;
        if (settingsState.joinNotificationEnabled) {
          HapticFeedback.lightImpact();
          _showGuestJoinedSnackbar(
            devices.where((d) => newDevices.contains(d.deviceId)).toList(),
          );
        }
      }

      _knownDeviceIds = currentIds;
    });
  }

  void _showGuestJoinedSnackbar(List<ConnectedDeviceInfo> newDevices) {
    if (!mounted) return;
    final names = newDevices.map((d) => d.deviceName).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎵 $names a rejoint la session'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _devicesSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _DeviceTile extends StatelessWidget {
  final ConnectedDeviceInfo device;

  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final syncQuality = device.syncQuality;
    final isHealthy = device.isHealthy;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Device type icon
          _buildDeviceIcon(context, isHealthy),

          const SizedBox(width: 12),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (device.ip.isNotEmpty)
                  Text(
                    device.ip,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Sync quality badge
          _buildSyncBadge(context, syncQuality),

          const SizedBox(width: 8),

          // Clock offset
          _buildOffsetDisplay(context),
        ],
      ),
    );
  }

  Widget _buildDeviceIcon(BuildContext context, bool isHealthy) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isHealthy
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          device.deviceType.icon,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildSyncBadge(BuildContext context, SyncQuality quality) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: quality.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: quality.color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sync,
            size: 12,
            color: quality.color,
          ),
          const SizedBox(width: 4),
          Text(
            quality.label,
            style: TextStyle(
              color: quality.color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetDisplay(BuildContext context) {
    final offset = device.clockOffsetMs;
    final color = offset.abs() < 30
        ? Colors.green
        : offset.abs() < 50
            ? Colors.orange
            : Colors.red;

    return SizedBox(
      width: 60,
      child: Text(
        '${offset.toStringAsFixed(1)}ms',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
        textAlign: TextAlign.end,
      ),
    );
  }
}
