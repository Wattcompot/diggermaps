import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Вертикальный рейл инструментов слева (Wikimapia, рисование, снимки,
/// центрирование, компас).
///
/// При `embedded == false` (по умолчанию) позиционирует себя сам — прежнее
/// поведение, совместимое с текущим вызовом из `MapScreen`. При
/// `embedded == true` возвращается только содержимое, которое размещает
/// `MapBottomDock` (тогда рейл не может пересечь нижнюю стопку).
class LeftPanel extends StatelessWidget {
  const LeftPanel({
    super.key,
    required this.mapController,
    required this.spectralActive,
    required this.onWikimapiaPressed,
    required this.onBrushPressed,
    required this.onSpectralPressed,
    required this.onSpectralLongPress,
    required this.onCenterPressed,
    required this.onCompassPressed,
    this.rotation,
    this.embedded = false,
  });

  final MapController mapController;
  final bool spectralActive;
  final VoidCallback onWikimapiaPressed;
  final VoidCallback onBrushPressed;
  final VoidCallback onSpectralPressed;
  final VoidCallback onSpectralLongPress;
  final VoidCallback onCenterPressed;
  final VoidCallback onCompassPressed;
  final double? rotation;

  /// Не позиционировать себя самостоятельно (для `MapBottomDock`).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angle = rotation ?? mapController.camera.rotation;
    final primary = theme.colorScheme.primary;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SquareButton(
          onPressed: onWikimapiaPressed,
          child: Text(
            'W',
            style: TextStyle(
              color: theme.iconTheme.color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SquareButton(
          onPressed: onBrushPressed,
          child: const Icon(Icons.brush, size: 22),
        ),
        const SizedBox(height: 8),
        _SquareButton(
          onPressed: onSpectralPressed,
          onLongPress: onSpectralLongPress,
          child: Icon(
            Icons.satellite_alt,
            color: spectralActive ? primary : theme.iconTheme.color,
            size: 22,
          ),
        ),
        const SizedBox(height: 8),
        _SquareButton(
          onPressed: onCenterPressed,
          child: const Icon(Icons.my_location, size: 24),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: angle.abs() > 0.01
              ? Padding(
                  key: const ValueKey('map-compass-visible'),
                  padding: const EdgeInsets.only(top: 8),
                  child: _SquareButton(
                    onPressed: onCompassPressed,
                    active: true,
                    opaque: true,
                    child: _CompassNeedle(rotationDegrees: angle),
                  ),
                )
              : const SizedBox.shrink(
                  key: ValueKey('map-compass-hidden'),
                ),
        ),
      ],
    );

    if (embedded) return content;
    return Positioned(
      left: 12,
      top: MediaQuery.sizeOf(context).height * 0.25,
      child: content,
    );
  }
}

/// Стрелка компаса: поворачивается вслед за картой, чтобы кнопка показывала
/// текущее направление на север. Красная половина — север.
class _CompassNeedle extends StatelessWidget {
  const _CompassNeedle({required this.rotationDegrees});

  final double rotationDegrees;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: rotationDegrees * math.pi / 180),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, radians, child) => Transform.rotate(
        angle: radians,
        child: child,
      ),
      child: SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(
          painter: _CompassNeedlePainter(
            northColor: const Color(0xFFE05A4F),
            southColor: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter({
    required this.northColor,
    required this.southColor,
  });

  final Color northColor;
  final Color southColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final halfWidth = size.width * 0.16;
    final north = Path()
      ..moveTo(center.dx, 1)
      ..lineTo(center.dx - halfWidth, center.dy)
      ..lineTo(center.dx + halfWidth, center.dy)
      ..close();
    final south = Path()
      ..moveTo(center.dx, size.height - 1)
      ..lineTo(center.dx - halfWidth, center.dy)
      ..lineTo(center.dx + halfWidth, center.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = northColor);
    canvas.drawPath(south, Paint()..color = southColor);
    canvas.drawCircle(center, 1.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) =>
      oldDelegate.northColor != northColor ||
      oldDelegate.southColor != southColor;
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.child,
    required this.onPressed,
    this.onLongPress,
    this.active = false,
    this.opaque = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool active;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final primary = theme.colorScheme.primary;
    // Активная кнопка раньше подменяла фон на primary с альфой 0.2 — поверх
    // карты это выглядело почти прозрачным. Теперь фон всегда непрозрачный,
    // а активное состояние показываем лёгкой подложкой и рамкой акцента.
    final background = active
        ? Color.alphaBlend(primary.withValues(alpha: 0.18), surface)
        : opaque
            ? surface
            : surface.withValues(alpha: 0.9);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: background,
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}
