// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
// `latlong2` экспортирует собственный `Path<T>`; скрываем его, чтобы `Path`
// ниже означал `dart:ui.Path` (силуэт глифа).
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/constants/map_layers.dart';
import '../../../services/tile_cache/network_tile_provider_factory.dart';

/// Глиф метки.
///
/// Один и тот же вид используется на карте, в списке объектов, в предпросмотре
/// пикера и на кнопке внешнего вида — поэтому форма рисуется общим
/// [MarkerShapePainter], а не набором «случайных» Material-иконок.
class MarkerShape extends StatelessWidget {
  const MarkerShape({
    super.key,
    required this.shape,
    required this.color,
    required this.size,
  });

  final String shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: MarkerShapePainter(shape: shape, color: color),
      ),
    );
  }
}

/// Рисует заполненный силуэт формы с контрастной обводкой.
///
/// Формы согласованы между собой: у всех одинаковая толщина обводки и один
/// стиль заливки, поэтому глиф читается и в маленьком размере (18–26 лог. px),
/// и в крупном (48+). Обводка выбирается по яркости заливки (чёрная на светлом,
/// белая на тёмном), чтобы глиф не сливался с подложкой.
class MarkerShapePainter extends CustomPainter {
  const MarkerShapePainter({required this.shape, required this.color});

  final String shape;
  final Color color;

  /// Канонизирует исторические значения формы.
  ///
  /// `pin` — основная форма; старые `place`/`location_on` и неизвестные
  /// значения тоже рисуются булавкой, чтобы сохранённые метки не пропадали.
  static String normalize(String shape) {
    switch (shape) {
      case 'square':
      case 'circle':
      case 'triangle':
      case 'star':
      case 'flag':
      case 'home':
      case 'work':
        return shape;
      default:
        return 'pin';
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroke = strokeWidthFor(size);
    final path = buildPath(size, strokeWidth: stroke);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = outlineColorFor(color)
        ..isAntiAlias = true,
    );
  }

  /// Толщина обводки, масштабируемая вместе с глифом.
  static double strokeWidthFor(Size size) =>
      (size.shortestSide * 0.10).clamp(1.0, 3.0);

  /// Контрастная обводка под заливку.
  static Color outlineColorFor(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.light
          ? const Color(0x99000000)
          : const Color(0xB3FFFFFF);

  /// Строит силуэт формы внутри квадрата [size].
  ///
  /// Отступ равен половине обводки, чтобы штрих не обрезался по краям.
  Path buildPath(Size size, {double? strokeWidth}) {
    final side = size.shortestSide;
    if (side <= 0) return Path();
    final stroke = strokeWidth ?? strokeWidthFor(size);
    final inset = stroke / 2 + side * 0.02;
    final extent = math.max(0.0, side - inset * 2);
    final rect = Rect.fromLTWH(inset, inset, extent, extent);
    return switch (normalize(shape)) {
      'circle' => _circle(rect),
      'square' => _square(rect),
      'triangle' => _triangle(rect),
      'star' => _star(rect),
      'home' => _home(rect),
      'flag' => _flag(rect),
      'work' => _briefcase(rect),
      _ => _pin(rect),
    };
  }

  static Path _circle(Rect rect) => Path()
    ..addOval(
        Rect.fromCircle(center: rect.center, radius: rect.shortestSide / 2));

  static Path _square(Rect rect) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide * 0.16)),
    );

  static Path _triangle(Rect rect) => Path()
    ..moveTo(rect.center.dx, rect.top)
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left, rect.bottom)
    ..close();

  static Path _star(Rect rect) {
    final center = rect.center;
    final outer = rect.shortestSide / 2;
    final inner = outer * 0.42;
    final path = Path()..moveTo(center.dx, center.dy - outer);
    for (var i = 1; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? outer : inner;
      path.lineTo(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
    }
    return path..close();
  }

  static Path _home(Rect rect) {
    final eave = rect.top + rect.height * 0.40;
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, eave)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, eave)
      ..close();
  }

  static Path _flag(Rect rect) {
    final poleWidth = rect.width * 0.12;
    final pole = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          rect.left + rect.width * 0.12, rect.top, poleWidth, rect.height),
      Radius.circular(poleWidth / 2),
    );
    final banner = Path()
      ..moveTo(rect.left + rect.width * 0.20, rect.top + rect.height * 0.10)
      ..lineTo(rect.right, rect.top + rect.height * 0.10)
      ..lineTo(rect.left + rect.width * 0.72, rect.top + rect.height * 0.32)
      ..lineTo(rect.right, rect.top + rect.height * 0.54)
      ..lineTo(rect.left + rect.width * 0.20, rect.top + rect.height * 0.54)
      ..close();
    return Path.combine(PathOperation.union, Path()..addRRect(pole), banner);
  }

  static Path _briefcase(Rect rect) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(
          rect.left, rect.top + rect.height * 0.30, rect.right, rect.bottom),
      Radius.circular(rect.width * 0.14),
    );
    final handleWidth = rect.width * 0.40;
    final handle = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.center.dx - handleWidth / 2,
          rect.top + rect.height * 0.04, handleWidth, rect.height * 0.30),
      Radius.circular(rect.width * 0.10),
    );
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      Path()..addRRect(handle),
    );
  }

  static Path _pin(Rect rect) {
    final headRadius = rect.width * 0.32;
    final headCenter = Offset(rect.center.dx, rect.top + headRadius);
    final head = Path()
      ..addOval(Rect.fromCircle(center: headCenter, radius: headRadius));
    final tail = Path()
      ..moveTo(
          headCenter.dx - headRadius * 0.78, headCenter.dy + headRadius * 0.62)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(
          headCenter.dx + headRadius * 0.78, headCenter.dy + headRadius * 0.62)
      ..close();
    return Path.combine(PathOperation.union, head, tail);
  }

  @override
  bool shouldRepaint(covariant MarkerShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

class MarkerMapPreview extends StatelessWidget {
  const MarkerMapPreview({
    super.key,
    required this.point,
    required this.shape,
    required this.colorHex,
    required this.size,
  });

  final LatLng point;
  final String shape;
  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tileProvider = kIsWeb
        ? createNetworkTileProvider()
        : const FMTCStore('base_layers').getTileProvider();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 120,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: MapLayers.esriWorldImagery,
              tileProvider: tileProvider,
              maxZoom: 18,
              panBuffer: 3,
              keepBuffer: 6,
              subdomains: MapLayers.tileSubdomains,
              userAgentPackageName: MapLayers.userAgentPackageName,
            ),
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: point,
                  width: size,
                  height: size,
                  child: MarkerShape(
                    shape: shape,
                    color: _parseColor(colorHex),
                    size: size,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseColor(String value) =>
      Color(int.parse(value.replaceFirst('#', '0xFF')));
}
