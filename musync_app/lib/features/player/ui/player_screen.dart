import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/core.dart';
import '../bloc/player_bloc.dart';
import 'position_slider.dart';

/// Main player screen with playback controls.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PlayerBloc(
        sessionManager: context.read<SessionManager>(),
      ),
      child: const _PlayerView(),
    );
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
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Track info
                _TrackInfo(track: state.currentTrack),

                const SizedBox(height: 32),

                // Position slider
                PositionSlider(
                  position: state.position,
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
                ),

                const SizedBox(height: 32),

                // Volume control
                _VolumeControl(
                  volume: state.volume,
                  onChanged: (volume) {
                    context.read<PlayerBloc>().add(VolumeChanged(volume));
                  },
                ),

                const SizedBox(height: 32),

                // File picker
                _FilePickerButton(
                  onFilePicked: (track) {
                    context.read<PlayerBloc>().add(LoadTrackRequested(track));
                  },
                  onAddToQueue: (track) {
                    context.read<PlayerBloc>().add(AddToQueueRequested(track));
                  },
                ),

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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              child: isCurrent
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
                            subtitle: track.artist != null
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
        ),
        const SizedBox(height: 16),
        Text(
          track!.title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (track!.artist != null) ...[
          const SizedBox(height: 4),
          Text(
            track!.artist!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final PlayerStatus status;
  final bool hasNext;
  final bool hasPrevious;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onSkipNext;
  final VoidCallback onSkipPrevious;

  const _PlaybackControls({
    required this.status,
    required this.hasNext,
    required this.hasPrevious,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onSkipNext,
    required this.onSkipPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = status == PlayerStatus.playing;
    final isLoading =
        status == PlayerStatus.loading || status == PlayerStatus.buffering;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
          IconButton(
            iconSize: 64,
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            ),
            onPressed: isPlaying ? onPause : onPlay,
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
      ],
    );
  }
}

class _VolumeControl extends StatelessWidget {
  final double volume;
  final ValueChanged<double> onChanged;

  const _VolumeControl({
    required this.volume,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          volume == 0
              ? Icons.volume_off
              : volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        Expanded(
          child: Slider(
            value: volume,
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(volume * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _FilePickerButton extends StatelessWidget {
  final ValueChanged<AudioTrack> onFilePicked;
  final ValueChanged<AudioTrack> onAddToQueue;

  const _FilePickerButton({
    required this.onFilePicked,
    required this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickFile(context, addToQueue: false),
          icon: const Icon(Icons.folder_open),
          label: const Text('Charger'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _pickFile(context, addToQueue: true),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Ajouter à la file'),
        ),
      ],
    );
  }

  Future<void> _pickFile(BuildContext context,
      {required bool addToQueue}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        if (file.path != null) {
          final track = AudioTrack.fromFilePath(file.path!);
          if (addToQueue) {
            onAddToQueue(track);
          } else {
            onFilePicked(track);
            // If multiple selected, add the rest to queue
            if (result.files.length > 1) {
              for (final remaining in result.files.skip(1)) {
                if (remaining.path != null && remaining.path != file.path) {
                  onAddToQueue(AudioTrack.fromFilePath(remaining.path!));
                }
              }
            }
            break;
          }
        }
      }
    }
  }
}
