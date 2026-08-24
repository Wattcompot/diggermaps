import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

ui.Path buildSmoothMapPath(
  MapCamera camera,
  Iterable<List<LatLng>> source,
) {
  final path = ui.Path();
  for (final linePoints in source) {
    final projected = linePoints.map(camera.latLngToScreenOffset).toList();
    if (projected.isEmpty) continue;
    path.moveTo(projected.first.dx, projected.first.dy);
    for (var index = 1; index < projected.length; index++) {
      final previous = projected[index - 1];
      final current = projected[index];
      final control = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(control.dx, control.dy, current.dx, current.dy);
    }
  }
  return path;
}

class TrackLineData {
  const TrackLineData({
    required this.points,
    required this.color,
    required this.selected,
  });

  final List<LatLng> points;
  final Color color;
  final bool selected;
}

class TrackLineLayer extends StatelessWidget {
  const TrackLineLayer({
    super.key,
    required this.lines,
    this.activeLine,
  });

  final List<TrackLineData> lines;
  final List<LatLng>? activeLine;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: TrackLinePainter(
            camera: MapCamera.of(context),
            lines: lines,
            activeLine: activeLine,
          ),
        ),
      ),
    );
  }
}

class TrackLinePainter extends CustomPainter {
  const TrackLinePainter({
    required this.camera,
    required this.lines,
    this.activeLine,
  });

  final MapCamera camera;
  final List<TrackLineData> lines;
  final List<LatLng>? activeLine;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final path = buildSmoothMapPath(camera, <List<LatLng>>[line.points]);
      if (line.selected) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 7
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (activeLine != null) {
      canvas.drawPath(
        buildSmoothMapPath(camera, <List<LatLng>>[activeLine!]),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrackLinePainter oldDelegate) => true;
}
