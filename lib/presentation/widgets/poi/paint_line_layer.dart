import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'track_line_layer.dart';

class PaintLineData {
  const PaintLineData({
    required this.points,
    required this.color,
    required this.selected,
  });

  final List<LatLng> points;
  final Color color;
  final bool selected;
}

class PaintLineLayer extends StatelessWidget {
  const PaintLineLayer({super.key, required this.lines});

  final List<PaintLineData> lines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: PaintLinePainter(
            camera: MapCamera.of(context),
            lines: lines,
          ),
        ),
      ),
    );
  }
}

class PaintLinePainter extends CustomPainter {
  const PaintLinePainter({required this.camera, required this.lines});

  final MapCamera camera;
  final List<PaintLineData> lines;

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
  }

  @override
  bool shouldRepaint(covariant PaintLinePainter oldDelegate) => true;
}
