import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/core.dart';
import '../../../features/player/ui/position_slider.dart';
import '../bloc/discovery_bloc.dart';

/// Screen for discovering and connecting to devices.
class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DiscoveryBloc(
        sessionManager: context.read<SessionManager>(),
      )..add(const StartScanning()),
      child: const _DiscoveryView(),
    );
  }
}

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView();

  void _showManualIpDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connexion manuelle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '192.168.1.100',
            labelText: 'Adresse IP de l\'hôte',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                Navigator.pop(dialogContext);
                final device = DeviceInfo(
                  id: ip,
                  name: 'Appareil ($ip)',
                  type: DeviceType.phone,
                  ip: ip,
                  port: 7890,
                  discoveredAt: DateTime.now(),
                );
                context.read<DiscoveryBloc>().add(
                      JoinSessionRequested(device),
                    );
              }
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MusyncMIMO'),
        actions: [
          BlocBuilder<DiscoveryBloc, DiscoveryState>(
            builder: (context, state) {
              if (state.status == DiscoveryStatus.hosting ||
                  state.status == DiscoveryStatus.joined) {
                return IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    context.read<DiscoveryBloc>().add(
                          const LeaveSessionRequested(),
                        );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocBuilder<DiscoveryBloc, DiscoveryState>(
        builder: (context, state) {
          switch (state.status) {
            case DiscoveryStatus.idle:
            case DiscoveryStatus.scanning:
              return _buildScanningView(context, state);
            case DiscoveryStatus.hosting:
              return _buildHostingView(context, state);
            case DiscoveryStatus.joining:
              return _buildJoiningView();
            case DiscoveryStatus.joined:
              return _buildJoinedView(context);
            case DiscoveryStatus.error:
              return _buildErrorView(context, state);
          }
        },
      ),
      floatingActionButton: BlocBuilder<DiscoveryBloc, DiscoveryState>(
        builder: (context, state) {
          if (state.status == DiscoveryStatus.idle ||
              state.status == DiscoveryStatus.scanning) {
            return FloatingActionButton.extended(
              onPressed: () {
                context.read<DiscoveryBloc>().add(
                      const HostSessionRequested(),
                    );
              },
              icon: const Icon(Icons.cast_connected),
              label: const Text('Créer un groupe'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildScanningView(BuildContext context, DiscoveryState state) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.surround_sound,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Appareils disponibles',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                state.status == DiscoveryStatus.scanning
                    ? 'Recherche en cours...'
                    : 'Appuyez pour rechercher',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),

        // Scan button
        if (state.status == DiscoveryStatus.idle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FilledButton.icon(
              onPressed: () {
                context.read<DiscoveryBloc>().add(
                      const StartScanning(),
                    );
              },
              icon: const Icon(Icons.search),
              label: const Text('Rechercher des appareils'),
            ),
          ),

        if (state.status == DiscoveryStatus.scanning)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),

        const SizedBox(height: 16),

        // Manual IP entry (for testing on emulators)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: OutlinedButton.icon(
            onPressed: () => _showManualIpDialog(context),
            icon: const Icon(Icons.edit),
            label: const Text('Saisir une IP manuellement'),
          ),
        ),

        const SizedBox(height: 16),

        // Device list
        Expanded(
          child: state.availableDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.devices_other,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun appareil trouvé',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Assurez-vous que les autres appareils\nont MusyncMIMO ouvert',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: state.availableDevices.length,
                  itemBuilder: (context, index) {
                    final device = state.availableDevices[index];
                    return _DeviceTile(
                      device: device,
                      onTap: () {
                        context.read<DiscoveryBloc>().add(
                              JoinSessionRequested(device),
                            );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHostingView(BuildContext context, DiscoveryState state) {
    final sessionManager = context.read<SessionManager>();
    final localIp = sessionManager.localIp ?? 'Inconnu';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cast_connected,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Groupe actif',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${state.connectedDeviceCount} appareil(s) connecté(s)',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          // Show local IP for manual connection
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  'Votre IP locale :',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  localIp,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                ),
                Text(
                  'Partagez cette IP pour connexion manuelle',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/player');
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ouvrir le lecteur'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              context.read<DiscoveryBloc>().add(
                    const LeaveSessionRequested(),
                  );
            },
            icon: const Icon(Icons.close),
            label: const Text('Fermer le groupe'),
          ),
        ],
      ),
    );
  }

  Widget _buildJoiningView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Connexion en cours...'),
          SizedBox(height: 8),
          Text(
            'Synchronisation des horloges',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinedView(BuildContext context) {
    final sessionManager = context.read<SessionManager>();

    return BlocBuilder<DiscoveryBloc, DiscoveryState>(
      builder: (context, state) {
        final hasTrack = state.currentTrack != null;
        final isPlaying = state.isPlaying;
        final position = state.position;
        final duration = state.duration;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Connecté à l\'hôte',
                      style: TextStyle(color: Colors.green[700]),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Track info
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  hasTrack ? Icons.music_note : Icons.music_off,
                  size: 80,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),

              // Track title
              Text(
                hasTrack ? state.currentTrack!.title : 'Aucun morceau',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasTrack && state.currentTrack!.artist != null) ...[
                const SizedBox(height: 4),
                Text(
                  state.currentTrack!.artist!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],

              const SizedBox(height: 24),

              // Playback state indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isPlaying 
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlaying ? Icons.play_arrow : Icons.pause,
                      size: 20,
                      color: isPlaying
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isPlaying ? 'Lecture en cours' : 'En pause',
                      style: TextStyle(
                        color: isPlaying
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Position slider (read-only for slave)
              if (hasTrack && duration != null)
                PositionSlider(
                  position: position,
                  duration: duration,
                  onSeek: (_) {}, // Slave cannot seek
                )
              else if (hasTrack)
                // Show indeterminate progress while loading
                const LinearProgressIndicator(),

              const Spacer(),

              // Volume control
              _VolumeSlider(
                onChanged: (value) {
                  sessionManager.audioEngine.setVolume(value);
                },
              ),

              const SizedBox(height: 16),

              // Disconnect button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.read<DiscoveryBloc>().add(
                          const LeaveSessionRequested(),
                        );
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Se déconnecter'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorView(BuildContext context, DiscoveryState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Erreur',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              state.errorMessage ?? 'Une erreur est survenue',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              context.read<DiscoveryBloc>().add(
                    const LeaveSessionRequested(),
                  );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceInfo device;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(device.type.icon),
      ),
      title: Text(device.name),
      subtitle: Text(device.ip),
      trailing: FilledButton.tonal(
        onPressed: onTap,
        child: const Text('Rejoindre'),
      ),
      onTap: onTap,
    );
  }
}

/// Volume slider with local state.
class _VolumeSlider extends StatefulWidget {
  final ValueChanged<double> onChanged;

  const _VolumeSlider({required this.onChanged});

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double _volume = 1.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          _volume == 0
              ? Icons.volume_off
              : _volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        Expanded(
          child: Slider(
            value: _volume,
            min: 0,
            max: 1,
            onChanged: (value) {
              setState(() => _volume = value);
              widget.onChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(_volume * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
