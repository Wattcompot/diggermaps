import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'track_line_layer.dart';

/// Одна рисуемая линия. [width] реально применяется painter'ом
/// (раньше толщина была жёстко зашита 3.5 и стиль не отражался на карте).
/// [segments] позволяет рисовать прерывистые штрихи одного рисунка
/// без соединительных линий между pan-жестами.
class PaintLineData {
  const PaintLineData({
    required this.points,
    required this.color,
    required this.selected,
    this.width = 3.5,
    this.segments,
  });

  final List<LatLng> points;
  final Color color;
  final bool selected;
  final double width;
  final List<List<LatLng>>? segments;

  /// Набор под-путей для отрисовки. Если сегменты не заданы — одна линия.
  List<List<LatLng>> get strokes {
    final value = segments;
    if (value == null || value.isEmpty) return <List<LatLng>>[points];
    return value;
  }

  /// Толщина «обводки» выделения.
  double get haloWidth => width + 3.5;
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
      final path = buildSmoothMapPath(camera, line.strokes);
      if (line.selected) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..strokeWidth = line.haloWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..strokeWidth = line.width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PaintLinePainter oldDelegate) => true;
}
