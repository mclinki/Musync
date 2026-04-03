import 'package:flutter/material.dart';
import '../../../core/utils/format.dart';

class PositionSlider extends StatefulWidget {
  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  const PositionSlider({
    super.key,
    required this.position,
    this.duration,
    required this.onSeek,
  });

  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  double? _dragValue;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration?.inMilliseconds.toDouble() ?? 0.0;
    final hasDuration = maxMs > 0;
    final currentMs = _isDragging
        ? _dragValue ?? 0.0
        : widget.position.inMilliseconds.toDouble().clamp(0.0, hasDuration ? maxMs : 0.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            // MED-013 fix: visually disable slider when no track loaded
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
                formatDuration(widget.position),
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
