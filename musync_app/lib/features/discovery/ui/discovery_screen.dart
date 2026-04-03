import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/core.dart';
import '../../../core/utils/format.dart';
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
    var disposed = false;
    void safeDispose() {
      if (!disposed) {
        disposed = true;
        controller.dispose();
      }
    }

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
            onPressed: () {
              Navigator.pop(dialogContext);
              safeDispose();
            },
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isEmpty) return;
              // Validate IP format (HIGH-008 fix)
              final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
              if (!ipRegex.hasMatch(ip)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Adresse IP invalide. Format attendu : 192.168.1.100'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              // Validate each octet is 0-255
              final octets = ip.split('.').map(int.parse).toList();
              if (octets.any((o) => o < 0 || o > 255)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Adresse IP invalide. Chaque octet doit être entre 0 et 255.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              safeDispose();
              if (!context.mounted) return;
              final device = DeviceInfo(
                id: ip,
                name: 'Appareil ($ip)',
                type: DeviceType.phone,
                ip: ip,
                port: kDefaultPort,
                discoveredAt: DateTime.now(),
              );
              context.read<DiscoveryBloc>().add(
                    JoinSessionRequested(device),
                  );
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    ).then((_) => safeDispose());
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
              return _buildJoiningView(context, state);
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

  Widget _buildJoiningView(BuildContext context, DiscoveryState state) {
    final hostName = state.hostDevice?.name ?? 'Hôte';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connexion à $hostName...'),
          const SizedBox(height: 8),
          const Text(
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
        final hostName = state.hostDevice?.name ?? 'Hôte';
        final hostIp = state.hostDevice?.ip ?? '';
        final syncQuality = state.syncQuality;
        final syncOffset = state.syncOffsetMs;
        final fileProgress = state.fileTransferProgress;
        final connectionDetail = state.connectionDetail;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Connection Status Card ──
              _ConnectionStatusCard(
                connectionDetail: connectionDetail,
                hostName: hostName,
                hostIp: hostIp,
                syncQuality: syncQuality,
                syncOffsetMs: syncOffset,
              ),

              const SizedBox(height: 16),

              // ── File Transfer Progress ──
              if (fileProgress != null && fileProgress < 1.0)
                _FileTransferCard(progress: fileProgress),

              if (fileProgress != null && fileProgress < 1.0)
                const SizedBox(height: 16),

              // ── Track Info Card ──
              _TrackInfoCard(
                track: state.currentTrack,
                isPlaying: isPlaying,
                position: position,
                duration: duration,
              ),

              const SizedBox(height: 16),

              // ── Playback Controls (read-only for slave) ──
              if (hasTrack && duration != null)
                _PlaybackInfoCard(
                  position: position,
                  duration: duration,
                  isPlaying: isPlaying,
                  onStop: () {
                    context.read<DiscoveryBloc>().add(const StopPlaybackRequested());
                  },
                )
              else if (hasTrack)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Chargement du morceau...'),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // ── Playlist from Host ──
              if (state.playlistTracks.isNotEmpty)
                _PlaylistCard(
                  tracks: state.playlistTracks,
                  currentIndex: state.playlistCurrentIndex,
                ),

              if (state.playlistTracks.isNotEmpty)
                const SizedBox(height: 16),

              const SizedBox(height: 16),

              // ── Volume Control ──
              _VolumeCard(
                onChanged: (value) {
                  sessionManager.audioEngine.setVolume(value);
                },
              ),

              const SizedBox(height: 16),

              // ── Disconnect Button ──
              OutlinedButton.icon(
                onPressed: () {
                  context.read<DiscoveryBloc>().add(
                        const LeaveSessionRequested(),
                      );
                },
                icon: const Icon(Icons.link_off),
                label: const Text('Se déconnecter'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
                    const StartScanning(),
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

// ── New Enhanced Widgets for Guest View ──

class _ConnectionStatusCard extends StatelessWidget {
  final ConnectionDetail connectionDetail;
  final String hostName;
  final String hostIp;
  final SyncQuality syncQuality;
  final double syncOffsetMs;

  const _ConnectionStatusCard({
    required this.connectionDetail,
    required this.hostName,
    required this.hostIp,
    required this.syncQuality,
    required this.syncOffsetMs,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = connectionDetail == ConnectionDetail.connected;
    final isReconnecting = connectionDetail == ConnectionDetail.reconnecting;
    final isError = connectionDetail == ConnectionDetail.error;

    final statusColor = isError
        ? Colors.red
        : isReconnecting
            ? Colors.orange
            : isConnected
                ? Colors.green
                : Colors.grey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.wifi
                      : isReconnecting
                          ? Icons.wifi_find
                          : isError
                              ? Icons.wifi_off
                              : Icons.wifi_tethering,
                  color: statusColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connectionDetail.label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Session avec $hostName',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Sync quality badge
                if (isConnected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: syncQuality.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: syncQuality.color, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync, size: 14, color: syncQuality.color),
                        const SizedBox(width: 4),
                        Text(
                          syncQuality.label,
                          style: TextStyle(
                            color: syncQuality.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const Divider(height: 24),

            // Details
            _InfoRow(
              icon: Icons.person,
              label: 'Hôte',
              value: hostName,
            ),
            if (hostIp.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.router,
                label: 'IP',
                value: hostIp,
                isMono: true,
              ),
            ],
            if (isConnected) ...[
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.speed,
                label: 'Décalage',
                value: '${syncOffsetMs.toStringAsFixed(1)} ms',
                valueColor: syncOffsetMs.abs() < 30
                    ? Colors.green
                    : syncOffsetMs.abs() < 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isMono;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isMono = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          '$label : ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: isMono ? 'monospace' : null,
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FileTransferCard extends StatelessWidget {
  final double progress;

  const _FileTransferCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.downloading,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfert de fichier',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                      ),
                      Text(
                        '$percent% reçu',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackInfoCard extends StatelessWidget {
  final AudioTrack? track;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;

  const _TrackInfoCard({
    required this.track,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = track != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Album art placeholder
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    hasTrack ? Icons.music_note : Icons.music_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  if (isPlaying)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Track title
            Text(
              hasTrack ? track!.title : 'Aucun morceau',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Artist
            if (hasTrack && track!.artist != null) ...[
              const SizedBox(height: 4),
              Text(
                track!.artist!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],

            // Album
            if (hasTrack && track!.album != null) ...[
              const SizedBox(height: 2),
              Text(
                track!.album!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],

            const SizedBox(height: 8),

            // Playback state chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPlaying
                    ? Colors.green.withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPlaying ? Icons.play_arrow : Icons.pause,
                    size: 16,
                    color: isPlaying
                        ? Colors.green[700]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPlaying ? 'En lecture' : 'En pause',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isPlaying
                          ? Colors.green[700]
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackInfoCard extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback? onStop;

  const _PlaybackInfoCard({
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 8),

            // Time labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDuration(position),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                Text(
                  formatDuration(duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Stop button + read-only indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onStop != null)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    iconSize: 32,
                    onPressed: onStop,
                    tooltip: 'Arrêter localement',
                  ),
                if (onStop != null) const SizedBox(width: 16),
                Icon(
                  Icons.lock,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  'Contrôlé par l\'hôte',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeCard extends StatefulWidget {
  final ValueChanged<double> onChanged;

  const _VolumeCard({required this.onChanged});

  @override
  State<_VolumeCard> createState() => _VolumeCardState();
}

class _VolumeCardState extends State<_VolumeCard> {
  double _volume = 1.0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.volume_up,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Volume local',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${(_volume * 100).round()}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _volume == 0
                      ? Icons.volume_off
                      : _volume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final int currentIndex;

  const _PlaylistCard({
    required this.tracks,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.queue_music,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Playlist (${tracks.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...tracks.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final isCurrent = index == currentIndex;
              final title = track['title'] as String? ?? 'Piste ${index + 1}';
              final artist = track['artist'] as String?;

              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: isCurrent
                      ? const Icon(Icons.play_arrow, size: 16, color: Colors.white)
                      : Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: artist != null
                    ? Text(artist, style: const TextStyle(fontSize: 11))
                    : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
