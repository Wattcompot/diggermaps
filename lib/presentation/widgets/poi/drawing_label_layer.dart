import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/drawing.dart';
import '../../../data/utils/measurement_utils.dart';
import '../../providers/drawing_controller.dart';

/// Одна подпись измерения в мировых координатах.
class MeasurementLabel {
  const MeasurementLabel(
    this.point,
    this.text, {
    this.emphasized = false,
  });

  final LatLng point;
  final String text;

  /// Итоговые подписи (периметр/площадь/сумма) — чуть жирнее.
  final bool emphasized;
}

/// Чистый (тестируемый) расчёт подписей.
///
/// * ruler: расстояние каждого сегмента + «Итого: …».
/// * planimeter/polygon: расстояние каждого сегмента и, начиная с 3 точек,
///   периметр и площадь.
List<MeasurementLabel> buildMeasurementLabels({
  required List<LatLng> points,
  List<List<LatLng>>? segments,
  required MapDrawingMode mode,
  required bool metric,
}) {
  if (points.length < 2) return const <MeasurementLabel>[];

  final labels = <MeasurementLabel>[];
  final strokes = (segments == null || segments.isEmpty)
      ? <List<LatLng>>[points]
      : segments.where((segment) => segment.length >= 2);

  for (final stroke in strokes) {
    for (var index = 0; index < stroke.length - 1; index++) {
      final first = stroke[index];
      final second = stroke[index + 1];
      labels.add(
        MeasurementLabel(
          _midpoint(first, second),
          MeasurementUtils.formatDistance(
            MeasurementUtils.calculateDistance(first, second),
            metric: metric,
          ),
        ),
      );
    }
  }

  final isArea =
      mode == MapDrawingMode.polygon || mode == MapDrawingMode.planimeter;
  if (isArea) {
    if (points.length >= 3) {
      final closed = <LatLng>[...points, points.first];
      labels.add(
        MeasurementLabel(
          points.last,
          'Периметр: '
          '${MeasurementUtils.formatDistance(MeasurementUtils.totalDistance(closed), metric: metric)}',
          emphasized: true,
        ),
      );
      labels.add(
        MeasurementLabel(
          _centroid(points),
          'Площадь: '
          '${MeasurementUtils.formatArea(MeasurementUtils.calculateArea(points), metric: metric)}',
          emphasized: true,
        ),
      );
    }
  } else {
    labels.add(
      MeasurementLabel(
        points.last,
        'Итого: '
        '${MeasurementUtils.formatDistance(MeasurementUtils.totalDistance(points), metric: metric)}',
        emphasized: true,
      ),
    );
  }
  return labels;
}

LatLng _midpoint(LatLng a, LatLng b) => LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );

LatLng _centroid(List<LatLng> points) {
  var lat = 0.0;
  var lon = 0.0;
  for (final point in points) {
    lat += point.latitude;
    lon += point.longitude;
  }
  return LatLng(lat / points.length, lon / points.length);
}

class DrawingLabelLayer extends StatelessWidget {
  const DrawingLabelLayer({
    super.key,
    this.activePoints = const <LatLng>[],
    this.activeSegments = const <List<LatLng>>[],
    this.activeMode = MapDrawingMode.view,
    this.showActiveRuler = false,
    this.drawings = const <Drawing>[],
    this.metric = true,
    this.animate = true,
  });

  final List<LatLng> activePoints;
  final List<List<LatLng>> activeSegments;
  final MapDrawingMode activeMode;

  /// Совместимость со старым API (mode == ruler).
  final bool showActiveRuler;
  final List<Drawing> drawings;
  final bool metric;
  final bool animate;

  MapDrawingMode get _effectiveMode {
    if (activeMode != MapDrawingMode.view) return activeMode;
    return showActiveRuler ? MapDrawingMode.ruler : MapDrawingMode.view;
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    final mode = _effectiveMode;
    if (mode == MapDrawingMode.ruler ||
        mode == MapDrawingMode.planimeter ||
        mode == MapDrawingMode.polygon) {
      for (final label in buildMeasurementLabels(
        points: activePoints,
        segments: activeSegments,
        mode: mode,
        metric: metric,
      )) {
        markers.add(_label(label));
      }
    }
    for (final drawing in drawings.where(
      (item) => item.visible && item.category == 'measurement',
    )) {
      final drawingMode = drawing.type == 'polygon'
          ? MapDrawingMode.planimeter
          : MapDrawingMode.ruler;
      for (final label in buildMeasurementLabels(
        points: drawing.points,
        mode: drawingMode,
        metric: metric,
      )) {
        markers.add(_label(label));
      }
    }
    return MarkerLayer(markers: markers);
  }

  Marker _label(MeasurementLabel label) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: label.emphasized ? 11 : 10,
      fontWeight: label.emphasized ? FontWeight.w600 : FontWeight.w400,
      height: 1.1,
    );
    // Компактная подпись: размер бокса считается по реальному тексту,
    // поэтому нет огромных чёрных прямоугольников.
    final painter = TextPainter(
      text: TextSpan(text: label.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width + 12;
    final height = painter.height + 6;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xCC1E1E1E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label.text, style: style, maxLines: 1),
    );

    return Marker(
      point: label.point,
      width: width,
      height: height,
      child: Center(
        child: animate
            ? TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * value,
                    child: child,
                  ),
                ),
                child: chip,
              )
            : chip,
      ),
    );
  }
}
