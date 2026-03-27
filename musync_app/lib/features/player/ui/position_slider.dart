import 'package:flutter/material.dart';

class PositionSlider extends StatefulWidget {
  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  const PositionSlider({
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
    final currentMs = _isDragging
        ? _dragValue ?? 0.0
        : widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: maxMs > 0 ? currentMs.clamp(0.0, maxMs) : 0.0,
            min: 0,
            max: maxMs > 0 ? maxMs : 1.0,
            onChanged: maxMs > 0
                ? (value) {
                    setState(() {
                      _dragValue = value;
                      _isDragging = true;
                    });
                  }
                : null,
            onChangeEnd: maxMs > 0
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
                _formatDuration(widget.position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                widget.duration != null
                    ? _formatDuration(widget.duration!)
                    : '--:--',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
