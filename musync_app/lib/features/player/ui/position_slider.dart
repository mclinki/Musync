import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/utils/format.dart';

/// Position slider that listens directly to a position stream
/// instead of going through BLoC state (HIGH-011 fix).
///
/// This avoids rebuilding the entire widget tree on every position tick (200ms).
/// Only the slider rebuilds when position changes.
class PositionSlider extends StatefulWidget {
  /// Stream of position updates from the audio engine.
  final Stream<Duration> positionStream;

  /// Static duration (only changes when track changes, not on every tick).
  final Duration? duration;

  /// Called when the user releases the slider.
  final ValueChanged<Duration> onSeek;

  const PositionSlider({
    super.key,
    required this.positionStream,
    this.duration,
    required this.onSeek,
  });

  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  double? _dragValue;
  bool _isDragging = false;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _positionSub = widget.positionStream.listen((position) {
      if (!_isDragging && mounted) {
        setState(() => _position = position);
      }
    });
  }

  @override
  void didUpdateWidget(PositionSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _positionSub?.cancel();
      _positionSub = widget.positionStream.listen((position) {
        if (!_isDragging && mounted) {
          setState(() => _position = position);
        }
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration?.inMilliseconds.toDouble() ?? 0.0;
    final hasDuration = maxMs > 0;
    final currentMs = _isDragging
        ? _dragValue ?? 0.0
        : _position.inMilliseconds.toDouble().clamp(0.0, hasDuration ? maxMs : 0.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            inactiveTrackColor: hasDuration
                ? null
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            thumbColor: hasDuration ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          child: Slider(
            value: hasDuration ? currentMs.clamp(0.0, maxMs) : 0.0,
            min: 0,
            max: hasDuration ? maxMs : 1.0,
            onChanged: hasDuration
                ? (value) {
                    setState(() {
                      _dragValue = value;
                      _isDragging = true;
                    });
                  }
                : null,
            onChangeEnd: hasDuration
                ? (value) {
                    setState(() {
                      _isDragging = false;
                      _dragValue = null;
                    });
                    widget.onSeek(Duration(milliseconds: value.round()));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(_position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                widget.duration != null
                    ? formatDuration(widget.duration!)
                    : '--:--',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
