import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/drawing.dart';
import '../../../data/utils/measurement_utils.dart';

class DrawingLabelLayer extends StatelessWidget {
  const DrawingLabelLayer({
    super.key,
    this.activePoints = const <LatLng>[],
    this.showActiveRuler = false,
    this.drawings = const <Drawing>[],
    this.metric = true,
  });

  final List<LatLng> activePoints;
  final bool showActiveRuler;
  final List<Drawing> drawings;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (showActiveRuler) _appendLabels(markers, activePoints);
    for (final drawing in drawings.where((item) =>
        item.visible &&
        item.category == 'measurement' &&
        item.type == 'line')) {
      _appendLabels(markers, drawing.points);
    }
    return MarkerLayer(markers: markers);
  }

  void _appendLabels(List<Marker> markers, List<LatLng> points) {
    if (points.length < 2) return;
    for (var index = 0; index < points.length - 1; index++) {
      final first = points[index];
      final second = points[index + 1];
      markers.add(
        _label(
          LatLng(
            (first.latitude + second.latitude) / 2,
            (first.longitude + second.longitude) / 2,
          ),
          MeasurementUtils.calculateDistance(first, second),
        ),
      );
    }
    markers.add(
      _label(
        points.last,
        MeasurementUtils.totalDistance(points),
        prefix: 'Итого: ',
      ),
    );
  }

  Marker _label(LatLng point, double meters, {String prefix = ''}) => Marker(
        point: point,
        width: 90,
        height: 22,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$prefix${MeasurementUtils.formatDistance(meters, metric: metric)}',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
      );
}
