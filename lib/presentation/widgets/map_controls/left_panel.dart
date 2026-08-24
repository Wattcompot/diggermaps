import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

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

  @override
  Widget build(BuildContext context) {
    final angle = rotation ?? mapController.camera.rotation;
    final primary = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: 12,
      top: MediaQuery.sizeOf(context).height * 0.25,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SquareButton(
            onPressed: onWikimapiaPressed,
            child: Text(
              'W',
              style: TextStyle(
                color: Theme.of(context).iconTheme.color,
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
              color:
                  spectralActive ? primary : Theme.of(context).iconTheme.color,
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
                      child: const Icon(Icons.explore, size: 22),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('map-compass-hidden'),
                  ),
          ),
        ],
      ),
    );
  }
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
    final background = opaque
        ? theme.colorScheme.surface
        : theme.colorScheme.surface.withValues(alpha: 0.9);
    return Material(
      color: active
          ? theme.colorScheme.primary.withValues(alpha: 0.2)
          : background,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 44, height: 44, child: Center(child: child)),
      ),
    );
  }
}
