import 'package:flutter/material.dart';

/// A screen-fixed crosshair used while selecting the point under the map
/// center. It deliberately ignores all pointer events so the map remains
/// draggable underneath it.
class CrosshairOverlay extends StatelessWidget {
  const CrosshairOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: CrosshairPainter()),
      ),
    );
  }
}

class CrosshairPainter extends CustomPainter {
  const CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const gapRadius = 22.0;
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final paint in [glowPaint, linePaint]) {
      canvas.drawLine(Offset(0, center.dy),
          Offset(center.dx - gapRadius, center.dy), paint);
      canvas.drawLine(Offset(center.dx + gapRadius, center.dy),
          Offset(size.width, center.dy), paint);
      canvas.drawLine(Offset(center.dx, 0),
          Offset(center.dx, center.dy - gapRadius), paint);
      canvas.drawLine(Offset(center.dx, center.dy + gapRadius),
          Offset(center.dx, size.height), paint);
      canvas.drawCircle(center, gapRadius, paint);
    }

    canvas.drawCircle(center, 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
