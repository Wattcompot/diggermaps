import 'dart:math' as math;

import 'package:flutter/material.dart';

class BottomActions extends StatelessWidget {
  const BottomActions({
    super.key,
    required this.following,
    required this.recording,
    required this.aiming,
    required this.shiftEnabled,
    required this.onGpsPressed,
    required this.onGpsLongPress,
    required this.onShiftPressed,
    required this.onMapsPressed,
    required this.onAimCancel,
    required this.onAimDone,
  });

  final bool following;
  final bool recording;
  final bool aiming;
  final bool shiftEnabled;
  final VoidCallback onGpsPressed;
  final VoidCallback onGpsLongPress;
  final VoidCallback onShiftPressed;
  final VoidCallback onMapsPressed;
  final VoidCallback onAimCancel;
  final VoidCallback onAimDone;

  @override
  Widget build(BuildContext context) {
    if (aiming) {
      return Positioned(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: math.min(250, MediaQuery.sizeOf(context).width - 96),
            height: 48,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAimCancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onAimDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA67B5B),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Positioned(
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _RoundAction(
            icon: Icons.my_location_rounded,
            label: 'GPS',
            active: following || recording,
            onPressed: onGpsPressed,
            onLongPress: onGpsLongPress,
          ),
          const SizedBox(height: 10),
          _RoundAction(
            icon: Icons.open_with,
            label: 'Сдвиг',
            onPressed: shiftEnabled ? onShiftPressed : null,
          ),
          const SizedBox(height: 10),
          _RoundAction(
            icon: Icons.map_outlined,
            label: 'Карты',
            onPressed: onMapsPressed,
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onLongPress,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Material(
            elevation: 3,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              onLongPress: onLongPress,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  icon,
                  color: onPressed == null
                      ? Theme.of(context).disabledColor
                      : active
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).iconTheme.color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      );
}
