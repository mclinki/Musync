import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/core.dart';
import '../../../core/models/playlist.dart' show RepeatMode;
import '../../../core/utils/format.dart';
import '../bloc/player_bloc.dart';
import 'position_slider.dart';
import 'host_dashboard.dart';

/// Main player screen with playback controls.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Use the existing PlayerBloc from the app level
    return const _PlayerView();
  }
}

class _PlayerView extends StatelessWidget {
  const _PlayerView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lecteur'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          BlocBuilder<PlayerBloc, PlayerState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.queue_music),
                tooltip: 'File d\'attente (${state.playlist.length})',
                onPressed: () => _showQueueSheet(context, state),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<PlayerBloc, PlayerState>(
        builder: (context, state) {
          final sessionManager = context.read<SessionManager>();
          final isHost = sessionManager.role == DeviceRole.host;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Host dashboard (only for host)
                if (isHost) ...[
                  const HostDashboardCard(),
                  const SizedBox(height: 16),
                ],

                // Track info
                _TrackInfo(track: state.currentTrack),

                const SizedBox(height: 32),

                // Position slider — HIGH-011 fix: listen directly to position stream
                // instead of going through BLoC state (avoids full tree rebuilds at 5Hz)
                PositionSlider(
                  positionStream: sessionManager.audioEngine.positionStream,
                  duration: state.duration,
                  onSeek: (position) {
                    context.read<PlayerBloc>().add(SeekRequested(position));
                  },
                ),

                const SizedBox(height: 32),

                // Playback controls
                _PlaybackControls(
                  status: state.status,
                  hasNext: state.hasNext,
                  hasPrevious: state.hasPrevious,
                  isShuffled: state.isShuffled,
                  repeatMode: state.playlist.repeatMode,
                  onPlay: () {
                    context.read<PlayerBloc>().add(const PlayRequested());
                  },
                  onPause: () {
                    context.read<PlayerBloc>().add(const PauseRequested());
                  },
                  onStop: () {
                    context.read<PlayerBloc>().add(const StopRequested());
                  },
                  onSkipNext: () {
                    context.read<PlayerBloc>().add(const SkipNextRequested());
                  },
                  onSkipPrevious: () {
                    context.read<PlayerBloc>().add(const SkipPreviousRequested());
                  },
                  onToggleShuffle: () {
                    context.read<PlayerBloc>().add(const ToggleShuffleRequested());
                  },
                  onToggleRepeat: () {
                    context.read<PlayerBloc>().add(const ToggleRepeatRequested());
                  },
                ),

                const SizedBox(height: 32),

                // Volume control — VOLUME 1: listens to system volume stream
                _VolumeControl(
                  volume: state.volume,
                  systemVolumeStream: context.read<PlayerBloc>().systemVolume.volumeStream,
                  onChanged: (volume) {
                    context.read<PlayerBloc>().add(VolumeChanged(volume));
                  },
                ),

                const SizedBox(height: 32),

                // File picker (contextual: load first or add to queue)
                _ContextualFilePickerButton(),

                // Queue info
                if (state.playlist.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'File d\'attente : ${state.playlist.currentIndex + 1}/${state.playlist.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],

                // Syncing indicator
                if (state.syncingFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Synchronisation de ${state.syncingFiles.length} fichier(s)...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                            ),
                      ),
                    ],
                  ),
                ],

                // Sync quality
                if (state.syncQualityLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sync: ${state.syncQualityLabel}${state.syncOffsetMs != null ? ' (${state.syncOffsetMs!.toStringAsFixed(1)}ms)' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],

                // Error message
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showQueueSheet(BuildContext context, PlayerState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.queue_music),
                    const SizedBox(width: 8),
                    Text(
                      'File d\'attente (${state.playlist.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (state.playlist.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep),
                        tooltip: 'Vider la file',
                        onPressed: () {
                          context
                              .read<PlayerBloc>()
                              .add(const ClearQueueRequested());
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Queue list
              Expanded(
                child: state.playlist.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.queue_music,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('File d\'attente vide'),
                            SizedBox(height: 8),
                            Text(
                              'Ajoutez des morceaux avec le bouton +',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: state.playlist.length,
                        itemBuilder: (context, index) {
                          final track = state.playlist.tracks[index];
                          final isCurrent =
                              index == state.playlist.currentIndex;
                          // Check if this track is currently syncing
                          final fileName = extractFileName(track.source);
                          final isSyncing = state.syncingFiles.contains(fileName);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              child: isSyncing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : isCurrent
                                      ? const Icon(Icons.play_arrow,
                                          color: Colors.white)
                                      : Text('${index + 1}'),
                            ),
                            title: Text(
                              track.title,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: isSyncing
                                ? const Text('Synchronisation...',
                                    style: TextStyle(color: Colors.orange))
                                : track.artist != null
                                    ? Text(track.artist!)
                                    : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () {
                                context.read<PlayerBloc>().add(
                                    RemoveFromQueueRequested(index));
                              },
                            ),
                            onTap: () {
                              // Jump to this track
                              final newPlaylist =
                                  state.playlist.goTo(index);
                              context.read<PlayerBloc>().add(
                                    LoadTrackRequested(
                                        newPlaylist.currentTrack!),
                                  );
                            },
                          ).animate().slideX(
                            begin: 0.2,
                            end: 0,
                            delay: (index * 50).ms,
                            duration: 300.ms,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  final AudioTrack? track;

  const _TrackInfo({this.track});

  @override
  Widget build(BuildContext context) {
    if (track == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun morceau sélectionné',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.music_note,
            size: 80,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, curve: Curves.easeOut)
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOut),
        const SizedBox(height: 16),
        Text(
          track!.title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        )
            .animate()
            .fadeIn(duration: 400.ms, curve: Curves.easeOut)
            .slideY(begin: 0.3, end: 0, duration: 400.ms, curve: Curves.easeOut),
        if (track!.artist != null) ...[
          const SizedBox(height: 4),
          Text(
            track!.artist!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut)
              .slideY(begin: 0.2, end: 0, duration: 400.ms, curve: Curves.easeOut),
        ],
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final PlayerStatus status;
  final bool hasNext;
  final bool hasPrevious;
  final bool isShuffled;
  final RepeatMode repeatMode;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  const _PlaybackControls({
    required this.status,
    required this.hasNext,
    required this.hasPrevious,
    required this.isShuffled,
    required this.repeatMode,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = status == PlayerStatus.playing;
    final isLoading =
        status == PlayerStatus.loading || status == PlayerStatus.buffering;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: isShuffled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: onToggleShuffle,
        ),

        const SizedBox(width: 4),

        // Skip previous
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_previous),
          onPressed: hasPrevious ? onSkipPrevious : null,
          color: hasPrevious
              ? null
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),

        const SizedBox(width: 8),

        // Stop
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.stop),
          onPressed: status != PlayerStatus.idle ? onStop : null,
        ),

        const SizedBox(width: 8),

        // Play/Pause
        if (isLoading)
          const SizedBox(
            width: 64,
            height: 64,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: IconButton(
              key: ValueKey(isPlaying),
              iconSize: 64,
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              ),
              onPressed: isPlaying ? onPause : onPlay,
            ),
          ),

        const SizedBox(width: 8),

        // Skip next
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_next),
          onPressed: hasNext ? onSkipNext : null,
          color: hasNext
              ? null
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),

        const SizedBox(width: 4),

        // Repeat
        IconButton(
          icon: Icon(
            repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: repeatMode != RepeatMode.off
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: onToggleRepeat,
        ),
      ],
    );
  }
}

class _VolumeControl extends StatefulWidget {
  final double volume;
  final Stream<double> systemVolumeStream;
  final ValueChanged<double> onChanged;

  const _VolumeControl({
    required this.volume,
    required this.systemVolumeStream,
    required this.onChanged,
  });

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  double? _dragValue;
  bool _isDragging = false;
  double _currentVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.volume;
    widget.systemVolumeStream.listen((volume) {
      if (!_isDragging && mounted) {
        setState(() => _currentVolume = volume);
      }
    });
  }

  @override
  void didUpdateWidget(_VolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _currentVolume = widget.volume;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayVolume = _isDragging ? (_dragValue ?? _currentVolume) : _currentVolume;

    return Row(
      children: [
        Icon(
          displayVolume == 0
              ? Icons.volume_off
              : displayVolume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        Expanded(
          child: Slider(
            value: displayVolume,
            min: 0,
            max: 1,
            onChanged: (value) {
              setState(() {
                _dragValue = value;
                _isDragging = true;
              });
            },
            onChangeEnd: (value) {
              setState(() {
                _isDragging = false;
                _dragValue = null;
              });
              widget.onChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(displayVolume * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ContextualFilePickerButton extends StatelessWidget {
  const _ContextualFilePickerButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerBloc, PlayerState>(
      builder: (context, state) {
        final isEmpty = state.playlist.isEmpty;
        final icon = isEmpty ? Icons.folder_open : Icons.playlist_add;
        final label = isEmpty ? 'Charger un premier morceau' : 'Ajouter à la file d\'attente';

        return OutlinedButton.icon(
          onPressed: () => _pickFiles(context, isEmpty),
          icon: Icon(icon),
          label: Text(label),
        );
      },
    );
  }

  Future<void> _pickFiles(BuildContext context, bool isEmpty) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );

    if (!context.mounted) return;

    if (result != null && result.files.isNotEmpty) {
      final bloc = context.read<PlayerBloc>();
      bool isFirst = isEmpty;
      for (final file in result.files) {
        if (file.path != null) {
          final track = await AudioTrack.fromFilePathWithMetadata(file.path!);
          if (isFirst) {
            bloc.add(LoadTrackRequested(track));
            isFirst = false;
          } else {
            bloc.add(AddToQueueRequested(track));
          }
        }
      }
    }
  }
}
