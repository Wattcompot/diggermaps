import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/drawing.dart';

class DrawingAnchorLayer extends StatelessWidget {
  const DrawingAnchorLayer({
    super.key,
    this.activePoints = const <LatLng>[],
    this.showActivePoints = false,
    this.drawings = const <Drawing>[],
  });

  final List<LatLng> activePoints;
  final bool showActivePoints;
  final List<Drawing> drawings;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (showActivePoints)
        ...activePoints.map(
          (point) => Marker(
            point: point,
            width: 12,
            height: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                border: Border.all(color: Colors.white),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
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
}
