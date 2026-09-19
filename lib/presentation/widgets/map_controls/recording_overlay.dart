import 'package:flutter/material.dart';

import '../../providers/track_recording_controller.dart';

/// Анимация появления/скрытия панели записи (280 мс, fade + slide).
///
/// Раньше это был один `RecordingOverlay` с двумя `Positioned` внутри. Теперь
/// статистика и контролы записи — самостоятельное содержимое, но анимация
/// осталась той же, поэтому она вынесена в общий переход.
class _RecordingPanelTransition extends StatefulWidget {
  const _RecordingPanelTransition({
    required this.visible,
    required this.childBuilder,
    this.pulse = false,
  });

  final bool visible;
  final bool pulse;
  final Widget Function(BuildContext context, Animation<double> pulse)
      childBuilder;

  @override
  State<_RecordingPanelTransition> createState() =>
      _RecordingPanelTransitionState();
}

class _RecordingPanelTransitionState extends State<_RecordingPanelTransition>
    with TickerProviderStateMixin {
  late final AnimationController _panelController;
  late final AnimationController _pulseController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _pulse;

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
    _panelController.addStatusListener(_handleStatus);
    _syncAnimation();
  }

  /// По завершении прямой/обратной анимации перестраиваемся: без этого
  /// свернувшаяся панель осталась бы в дереве до следующего внешнего события.
  void _handleStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingPanelTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.pulse != widget.pulse) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.visible) {
      _panelController.forward();
      if (widget.pulse && !_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _panelController.reverse();
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _panelController.removeStatusListener(_handleStatus);
    _panelController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _panelController.isDismissed) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.childBuilder(context, _pulse),
      ),
    );
  }
}

/// Карточка статистики записи трека (содержимое, без позиционирования).
class RecordingStatsCard extends StatelessWidget {
  const RecordingStatsCard({
    super.key,
    required this.isRecording,
    required this.isPaused,
    required this.speedKmh,
    required this.distanceKm,
  });

  final bool isRecording;
  final bool isPaused;
  final double speedKmh;
  final double distanceKm;

  @override
  Widget build(BuildContext context) => _RecordingPanelTransition(
        visible: isRecording,
        pulse: true,
        childBuilder: (context, pulse) => _RecordingStatsContent(
          isPaused: isPaused,
          speedKmh: speedKmh,
          distanceKm: distanceKm,
          pulse: pulse,
        ),
      );
}

/// Контролы записи трека (содержимое, без позиционирования).
class RecordingControlsPanel extends StatelessWidget {
  const RecordingControlsPanel({
    super.key,
    required this.isRecording,
    required this.isPaused,
    required this.onStop,
    required this.onTogglePause,
    required this.onCancel,
  });

  final bool isRecording;
  final bool isPaused;
  final VoidCallback onStop;
  final VoidCallback onTogglePause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => _RecordingPanelTransition(
        visible: isRecording,
        childBuilder: (context, _) => _RecordingControlsContent(
          isPaused: isPaused,
          onStop: onStop,
          onTogglePause: onTogglePause,
          onCancel: onCancel,
        ),
      );
}

/// Карточка статистики записи, привязанная к контроллеру.
class TrackRecordingStatsCard extends StatelessWidget {
  const TrackRecordingStatsCard({super.key, required this.controller});

  final TrackRecordingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => RecordingStatsCard(
          isRecording: controller.isRecording,
          isPaused: controller.isPaused,
          speedKmh: controller.currentSpeed,
          distanceKm: controller.distance / 1000,
        ),
      );
}

/// Контролы записи, привязанные к контроллеру.
class TrackRecordingControlsPanel extends StatelessWidget {
  const TrackRecordingControlsPanel({
    super.key,
    required this.controller,
    required this.onStop,
    required this.onCancel,
  });

  final TrackRecordingController controller;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => RecordingControlsPanel(
          isRecording: controller.isRecording,
          isPaused: controller.isPaused,
          onStop: onStop,
          onTogglePause: controller.togglePause,
          onCancel: onCancel,
        ),
      );
}

/// Прежний оверлей записи: сам позиционирует статистику и контролы.
///
/// Оставлен для совместимости с текущим вызовом из `MapScreen`. Для
/// `MapBottomDock` используйте [TrackRecordingStatsCard] (слот `stats`) и
/// [TrackRecordingControlsPanel] (в `panels`).
class RecordingOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: <Widget>[
        Positioned(
          top: padding.top + 150,
          right: 16,
          child: TrackRecordingStatsCard(controller: controller),
        ),
        Positioned(
          left: 16,
          right: 88,
          bottom: padding.bottom + (spectralVisible ? 72 : 16),
          child: TrackRecordingControlsPanel(
            controller: controller,
            onStop: onStop,
            onCancel: onCancel,
          ),
        ),
      ],
    );
  }
}

class _RecordingStatsContent extends StatelessWidget {
  const _RecordingStatsContent({
    required this.isPaused,
    required this.speedKmh,
    required this.distanceKm,
    required this.pulse,
  });

  final bool isPaused;
  final double speedKmh;
  final double distanceKm;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => Container(
        width: 206,
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
                Expanded(
                  child: Text(
                    isPaused ? 'Запись приостановлена' : 'Идёт запись трека',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
                    value: '${speedKmh.toStringAsFixed(1)} км/ч',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    icon: Icons.straighten,
                    iconColor: Colors.blue,
                    value: '${distanceKm.toStringAsFixed(2)} км',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RecordingControlsContent extends StatelessWidget {
  const _RecordingControlsContent({
    required this.isPaused,
    required this.onStop,
    required this.onTogglePause,
    required this.onCancel,
  });

  final bool isPaused;
  final VoidCallback onStop;
  final VoidCallback onTogglePause;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 64),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.stop, size: 18),
                label: const FittedBox(child: Text('Стоп')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: onTogglePause,
                style: FilledButton.styleFrom(
                  backgroundColor: isPaused
                      ? const Color(0xFFA67B5B)
                      : Colors.blueGrey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                  isPaused ? Icons.play_arrow : Icons.pause,
                  size: 18,
                ),
                label: FittedBox(
                  child: Text(isPaused ? 'Продолжить' : 'Пауза'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
