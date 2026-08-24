import 'package:flutter/material.dart';

import '../../providers/map_calibration_controller.dart';

class CalibrationControls extends StatelessWidget {
  const CalibrationControls({
    super.key,
    required this.controller,
  });

  final MapCalibrationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final map = controller.activeCalibrationMap;
        if (map == null) return const SizedBox.shrink();
        return _CalibrationPanel(
          mapName: map.name,
          stepMeters: controller.calibrationStepMeters,
          onStepChanged: controller.setStepMeters,
          onShift: controller.shiftActiveMap,
          onReset: controller.resetActiveMapOffset,
          onDone: controller.finish,
        );
      },
    );
  }
}

class _CalibrationPanel extends StatelessWidget {
  const _CalibrationPanel({
    required this.mapName,
    required this.stepMeters,
    required this.onStepChanged,
    required this.onShift,
    required this.onReset,
    required this.onDone,
  });

  final String mapName;
  final int stepMeters;
  final ValueChanged<int> onStepChanged;
  final void Function(int x, int y) onShift;
  final VoidCallback onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelColor = theme.brightness == Brightness.dark
        ? const Color(0xCC1E1E1E)
        : theme.colorScheme.surface.withValues(alpha: 0.96);
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.paddingOf(context).bottom + 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            width: 230,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: stepMeters.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '$stepMeters м',
                    activeColor: const Color(0xFFA67B5B),
                    inactiveColor: Colors.grey,
                    onChanged: (value) => onStepChanged(value.round()),
                  ),
                ),
                SizedBox(width: 42, child: Text('$stepMeters м')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _DPad(
            panelColor: panelColor,
            onShift: onShift,
            onReset: onReset,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Сдвиг: $mapName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFA67B5B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onDone,
                  child: const Text('Готово'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({
    required this.panelColor,
    required this.onShift,
    required this.onReset,
  });

  final Color panelColor;
  final void Function(int x, int y) onShift;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, int x, int y, {bool reset = false}) =>
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(28),
          ),
          child: IconButton(
            icon: Icon(icon, size: 20),
            onPressed: reset ? onReset : () => onShift(x, y),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            button(Icons.north_west, -1, 1),
            const SizedBox(width: 8),
            button(Icons.arrow_upward, 0, 1),
            const SizedBox(width: 8),
            button(Icons.north_east, 1, 1),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            button(Icons.arrow_back, -1, 0),
            const SizedBox(width: 8),
            button(Icons.adjust, 0, 0, reset: true),
            const SizedBox(width: 8),
            button(Icons.arrow_forward, 1, 0),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            button(Icons.south_west, -1, -1),
            const SizedBox(width: 8),
            button(Icons.arrow_downward, 0, -1),
            const SizedBox(width: 8),
            button(Icons.south_east, 1, -1),
          ],
        ),
      ],
    );
  }
}
