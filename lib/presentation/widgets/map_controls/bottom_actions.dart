import 'package:flutter/material.dart';

/// Кнопки режима прицеливания («Отмена» / «Готово»).
///
/// Содержимое без позиционирования: размещением занимается [MapBottomDock]
/// (или legacy-режим [BottomActions]).
class AimActions extends StatelessWidget {
  const AimActions({
    super.key,
    required this.onCancel,
    required this.onDone,
  });

  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250, minHeight: 48),
          child: Row(
            children: <Widget>[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const FittedBox(child: Text('Отмена')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA67B5B),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check),
                  label: const FittedBox(child: Text('Готово')),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Экшен-рейл по умолчанию: GPS, «Сдвиг», «Карты».
///
/// Содержимое без позиционирования: размещением занимается [MapBottomDock]
/// (или legacy-режим [BottomActions]).
class ActionRail extends StatelessWidget {
  const ActionRail({
    super.key,
    required this.following,
    required this.recording,
    required this.shiftEnabled,
    required this.onGpsPressed,
    required this.onGpsLongPress,
    required this.onShiftPressed,
    required this.onMapsPressed,
  });

  final bool following;
  final bool recording;
  final bool shiftEnabled;
  final VoidCallback onGpsPressed;
  final VoidCallback onGpsLongPress;
  final VoidCallback onShiftPressed;
  final VoidCallback onMapsPressed;

  @override
  Widget build(BuildContext context) => Column(
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
      );
}

/// Кнопки карты внизу: либо рейл действий, либо кнопки прицеливания.
///
/// При `embedded == false` (по умолчанию) виджет позиционирует себя сам —
/// прежнее поведение, совместимое с текущим вызовом из `MapScreen`. При
/// `embedded == true` возвращается только содержимое ([ActionRail] или
/// [AimActions]) для размещения внутри [MapBottomDock].
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
    this.embedded = false,
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

  /// Не позиционировать себя самостоятельно (для [MapBottomDock]).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (aiming) {
      final actions = AimActions(onCancel: onAimCancel, onDone: onAimDone);
      if (embedded) return actions;
      return Positioned(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
        child: actions,
      );
    }

    final rail = ActionRail(
      following: following,
      recording: recording,
      shiftEnabled: shiftEnabled,
      onGpsPressed: onGpsPressed,
      onGpsLongPress: onGpsLongPress,
      onShiftPressed: onShiftPressed,
      onMapsPressed: onMapsPressed,
    );
    if (embedded) return rail;
    return Positioned(
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: rail,
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
