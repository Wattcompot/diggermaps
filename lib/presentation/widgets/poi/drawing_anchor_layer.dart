import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/drawing.dart';

class DrawingAnchorLayer extends StatelessWidget {
  const DrawingAnchorLayer({
    super.key,
    this.activePoints = const <LatLng>[],
    this.showActivePoints = false,
    this.activeColor,
    this.drawings = const <Drawing>[],
    this.animate = true,
  });

  final List<LatLng> activePoints;
  final bool showActivePoints;

  /// Цвет активных узлов — обычно совпадает с цветом текущего стиля.
  final Color? activeColor;
  final List<Drawing> drawings;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (showActivePoints) ...activePoints.map(_activeMarker),
      ...drawings
          .where((drawing) =>
              drawing.visible &&
              (drawing.category == 'measurement' || drawing.type == 'polygon'))
          .expand(
            (drawing) => drawing.points.map(
              (point) => Marker(
                point: point,
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey[300]!,
                    border: Border.all(color: Colors.white, width: 1.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
    ];
    return MarkerLayer(markers: markers);
  }

  Marker _activeMarker(LatLng point) => Marker(
        point: point,
        width: 20,
        height: 20,
        child: Center(
          child: animate
              ? TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.6, end: 1.0),
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: _activeDot,
                )
              : _activeDot,
        ),
      );

  DecoratedBox get _activeDot => DecoratedBox(
        decoration: BoxDecoration(
          color: activeColor ?? Colors.grey[300],
          border: Border.all(color: Colors.white, width: 1.5),
          shape: BoxShape.circle,
        ),
        child: const SizedBox(width: 12, height: 12),
      );
}
