import 'package:flutter/material.dart';

import '../../providers/track_recording_controller.dart';

class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({
    super.key,
    required this.controller,
    required this.onStop,
    required this.onCancel,
    required this.spectralVisible,
  });

  final TrackRecordingController controller;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final bool spectralVisible;

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _panelController;
  late final AnimationController _pulseController;
  late final Animation<double> _opacity;
  late final Animation<double> _pulse;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = CurvedAnimation(parent: _panelController, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(_opacity);
    _pulse = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    widget.controller.addListener(_syncAnimation);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RecordingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncAnimation);
      widget.controller.addListener(_syncAnimation);
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.controller.isRecording) {
      _panelController.forward();
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _panelController.reverse();
      _pulseController.stop();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncAnimation);
    _panelController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isRecording && _panelController.isDismissed) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: <Widget>[
        Positioned(
          top: MediaQuery.paddingOf(context).top + 150,
          right: 16,
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: _RecordingStats(
                controller: widget.controller,
                pulse: _pulse,
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 88,
          bottom: MediaQuery.paddingOf(context).bottom +
              (widget.spectralVisible ? 72 : 16),
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: _RecordingControls(
                controller: widget.controller,
                onStop: widget.onStop,
                onCancel: widget.onCancel,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingStats extends StatelessWidget {
  const _RecordingStats({required this.controller, required this.pulse});

  final TrackRecordingController controller;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => Container(
        width: 206,
        constraints: const BoxConstraints(maxHeight: 110),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                FadeTransition(
                  opacity: pulse,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 10, height: 10),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  controller.isPaused
                      ? 'Запись приостановлена'
                      : 'Идёт запись трека',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Metric(
                    icon: Icons.speed,
                    iconColor: Colors.orange,
                    value: '${controller.currentSpeed.toStringAsFixed(1)} км/ч',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    icon: Icons.straighten,
                    iconColor: Colors.blue,
                    value:
                        '${(controller.distance / 1000).toStringAsFixed(2)} км',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({
    required this.controller,
    required this.onStop,
    required this.onCancel,
  });

  final TrackRecordingController controller;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop, size: 18),
                label: const FittedBox(child: Text('Стоп')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.togglePause,
                style: FilledButton.styleFrom(
                  backgroundColor: controller.isPaused
                      ? const Color(0xFFA67B5B)
                      : Colors.blueGrey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: Icon(
                  controller.isPaused ? Icons.play_arrow : Icons.pause,
                  size: 18,
                ),
                label: FittedBox(
                  child: Text(controller.isPaused ? 'Продолжить' : 'Пауза'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: onCancel,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const FittedBox(child: Text('Отмена')),
              ),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.iconColor,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, color: iconColor, size: 19),
          const SizedBox(width: 5),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: FittedBox(
                key: ValueKey(value),
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}
