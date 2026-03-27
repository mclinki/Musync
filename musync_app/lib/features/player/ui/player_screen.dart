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
                  onPlay: () {
                    context.read<PlayerBloc>().add(const PlayRequested());
                  },
                  onPause: () {
                    context.read<PlayerBloc>().add(const PauseRequested());
                  },
                  onStop: () {
                    context.read<PlayerBloc>().add(const StopRequested());
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
                ),

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
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;

  const _PlaybackControls({
    required this.status,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = status == PlayerStatus.playing;
    final isLoading = status == PlayerStatus.loading ||
        status == PlayerStatus.buffering;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Stop
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.stop),
          onPressed: status != PlayerStatus.idle ? onStop : null,
        ),

        const SizedBox(width: 16),

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

        const SizedBox(width: 16),

        // Skip (placeholder)
        IconButton(
          iconSize: 40,
          icon: const Icon(Icons.skip_next),
          onPressed: null, // TODO: implement skip
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

  const _FilePickerButton({required this.onFilePicked});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _pickFile(context),
      icon: const Icon(Icons.folder_open),
      label: const Text('Choisir un fichier audio'),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        final track = AudioTrack.fromFilePath(file.path!);
        onFilePicked(track);
      }
    }
  }
}
