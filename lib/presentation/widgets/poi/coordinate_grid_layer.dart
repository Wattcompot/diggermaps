import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Геометрия сетки. Чистые вычисления, без зависимости от камеры —
/// покрыты тестами.
abstract final class CoordinateGridGeometry {
  /// Максимальная широта проекции Меркатора (EPSG:3857).
  static const double maxLatitude = 85.0511287798;

  /// Метров на градус широты (средняя величина для Меркатора).
  static const double metersPerDegreeLatitude = 111320.0;

  static const double _feetPerMeter = 3.280839895013123;
  static const double _baseMetersPerPixelAtEquator = 156543.03392;

  /// «Красивые» шаги сетки (1/2/5 × 10ⁿ), метры.
  static const List<double> metricStepsMeters = <double>[
    1,
    2,
    5,
    10,
    20,
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
    200000,
    500000,
    1000000,
    2000000,
    5000000,
    10000000,
  ];

  /// «Красивые» шаги для имперской системы (футы, включая ровные мили).
  static const List<double> imperialStepsFeet = <double>[
    3,
    5,
    10,
    15,
    25,
    50,
    100,
    250,
    500,
    1000,
    2000,
    2640,
    5280,
    10560,
    26400,
    52800,
    105600,
    264000,
  ];

  /// Метров в пикселе для широты [latitude] и зума [zoom].
  static double metersPerPixel(double latitude, double zoom) {
    final clamped = latitude.clamp(-maxLatitude, maxLatitude);
    return _baseMetersPerPixelAtEquator *
        math.cos(clamped * math.pi / 180) /
        math.pow(2, zoom);
  }

  /// Приводит долготу к диапазону [-180, 180).
  static double wrapLongitude(double longitude) {
    var value = longitude % 360;
    if (value >= 180) value -= 360;
    if (value < -180) value += 360;
    return value;
  }

  /// Форматирует шаг сетки для подписи.
  static String formatStep(double meters, bool metricUnits) {
    if (metricUnits) {
      if (meters >= 1000) return '${_trim(meters / 1000)} км';
      return '${_trim(meters)} м';
    }
    final feet = meters * _feetPerMeter;
    if (feet >= 5280) return '${_trim(feet / 5280)} миль';
    return '${_trim(feet)} фут';
  }

  static String _trim(double value) {
    if (value >= 100) return value.round().toString();
    final rounded = value.toStringAsFixed(value >= 10 ? 0 : 1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }

  /// Доля градуса, которую стоит показывать в подписи координаты.
  static int decimalsForStep(double stepDegrees) {
    if (stepDegrees <= 0 || !stepDegrees.isFinite) return 6;
    final decimals = (-(math.log(stepDegrees) / math.ln10)).ceil();
    return decimals.clamp(0, 6);
  }
}

/// Подобранный шаг сетки для текущего зума/широты.
@immutable
class CoordinateGridSpec {
  const CoordinateGridSpec({
    required this.latStepDegrees,
    required this.lngStepDegrees,
    required this.stepMeters,
    required this.metricUnits,
  });

  final double latStepDegrees;
  final double lngStepDegrees;
  final double stepMeters;
  final bool metricUnits;

  /// Шаг подбирается по масштабу (зум + широта): целевое расстояние между
  /// линиями ≈ [targetSpacingPixels], шаг округляется до «красивого».
  /// Меридианы идут чаще по градусам с ростом широты, чтобы ячейки оставались
  /// примерно квадратными в метрах.
  factory CoordinateGridSpec.forCamera({
    required double latitude,
    required double zoom,
    required bool metricUnits,
    double targetSpacingPixels = 96,
  }) {
    final clampedLatitude = latitude.clamp(-CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final metersPerPixel =
        CoordinateGridGeometry.metersPerPixel(clampedLatitude, zoom);
    final targetMeters =
        (metersPerPixel * targetSpacingPixels).clamp(0.5, 2.0e7);
    final steps = metricUnits
        ? CoordinateGridGeometry.metricStepsMeters
        : CoordinateGridGeometry.imperialStepsFeet
            .map((feet) => feet * 0.3048)
            .toList(growable: false);
    var selected = steps.last;
    for (final step in steps) {
      if (step >= targetMeters) {
        selected = step;
        break;
      }
    }
    final latStep = selected / CoordinateGridGeometry.metersPerDegreeLatitude;
    final cosLatitude =
        math.cos(clampedLatitude * math.pi / 180).abs().clamp(0.02, 1.0);
    return CoordinateGridSpec(
      latStepDegrees: latStep,
      lngStepDegrees: latStep / cosLatitude,
      stepMeters: selected,
      metricUnits: metricUnits,
    );
  }
}

/// Линии сетки в мировых координатах (кратны шагу => привязаны к миру,
/// а не к текущему положению камеры).
@immutable
class CoordinateGridLines {
  const CoordinateGridLines({
    required this.latitudes,
    required this.longitudes,
    required this.latStepDegrees,
    required this.lngStepDegrees,
  });

  final List<double> latitudes;
  final List<double> longitudes;
  final double latStepDegrees;
  final double lngStepDegrees;

  static CoordinateGridLines build({
    required double south,
    required double north,
    required double west,
    required double east,
    required CoordinateGridSpec spec,
    int maxLines = 96,
  }) {
    final latFrom = south.clamp(-CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final latTo = north.clamp(-CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final lngSpan = (east - west).abs().clamp(0.0, 360.0);
    final boundedEast =
        lngSpan == 0 ? west : (east > west ? west + lngSpan : west - lngSpan);

    var latitudes = const <double>[];
    var longitudes = const <double>[];
    var latStep = spec.latStepDegrees;
    var lngStep = spec.lngStepDegrees;

    for (var attempt = 0; attempt < 12; attempt++) {
      final multiplier = _multiplierSequence(attempt);
      latStep = spec.latStepDegrees * multiplier;
      lngStep = spec.lngStepDegrees * multiplier;
      // Округление наружу может дать линии за границей Меркатора: их
      // выбрасываем, а не пытаемся спроецировать.
      latitudes = _multiples(latFrom, latTo, latStep, maxLines * 4)
          .where((latitude) =>
              latitude.abs() <= CoordinateGridGeometry.maxLatitude)
          .toList(growable: false);
      longitudes = _multiples(west, boundedEast, lngStep, maxLines * 4);
      if (latitudes.length <= maxLines && longitudes.length <= maxLines) break;
    }

    return CoordinateGridLines(
      latitudes: latitudes,
      longitudes: longitudes,
      latStepDegrees: latStep,
      lngStepDegrees: lngStep,
    );
  }

  static double _multiplierSequence(int index) {
    const mantissas = <double>[1, 2, 5];
    final decade = math.pow(10, index ~/ mantissas.length).toDouble();
    return decade * mantissas[index % mantissas.length];
  }

  static List<double> _multiples(
    double from,
    double to,
    double step,
    int hardLimit,
  ) {
    if (!step.isFinite || step <= 0 || !from.isFinite || !to.isFinite) {
      return const <double>[];
    }
    final lower = math.min(from, to);
    final upper = math.max(from, to);
    final first = (lower / step).floor();
    final last = (upper / step).ceil();
    if (last - first > hardLimit) return const <double>[];
    final values = <double>[];
    for (var i = first; i <= last; i++) {
      values.add(i * step);
    }
    return values;
  }
}

/// Адаптивная координатная сетка.
///
/// Собственный слой, независимый от тайлов: работает поверх любой карты
/// (в том числе примитивных/растровых), шаг 1/2/5 подбирается по зуму и
/// широте, число линий ограничено (~100), линии привязаны к мировым
/// координатам, корректны при повороте и переносе через 180°.
class CoordinateGridLayer extends StatelessWidget {
  const CoordinateGridLayer({
    super.key,
    this.metricUnits = true,
    this.targetSpacingPixels = 96,
    this.maxLines = 96,
    this.lineColor = const Color(0xB3FFFFFF),
    this.haloColor = const Color(0x59000000),
    this.labelColor = const Color(0xFF12161A),
  });

  final bool metricUnits;
  final double targetSpacingPixels;
  final int maxLines;
  final Color lineColor;
  final Color haloColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: CoordinateGridPainter(
            camera: MapCamera.of(context),
            metricUnits: metricUnits,
            targetSpacingPixels: targetSpacingPixels,
            maxLines: maxLines,
            lineColor: lineColor,
            haloColor: haloColor,
            labelColor: labelColor,
          ),
        ),
      ),
    );
  }
}

class CoordinateGridPainter extends CustomPainter {
  const CoordinateGridPainter({
    required this.camera,
    required this.metricUnits,
    this.targetSpacingPixels = 96,
    this.maxLines = 96,
    this.lineColor = const Color(0xB3FFFFFF),
    this.haloColor = const Color(0x59000000),
    this.labelColor = const Color(0xFF12161A),
  });

  final MapCamera camera;
  final bool metricUnits;
  final double targetSpacingPixels;
  final int maxLines;
  final Color lineColor;
  final Color haloColor;
  final Color labelColor;

  static const double _backingCoverage = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.isEmpty || !camera.zoom.isFinite) return;

    final bounds = camera.visibleBounds;
    final centerLatitude = camera.center.latitude.clamp(
        -CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final spec = CoordinateGridSpec.forCamera(
      latitude: centerLatitude,
      zoom: camera.zoom,
      metricUnits: metricUnits,
      targetSpacingPixels: targetSpacingPixels,
    );

    final latFrom = bounds.south.clamp(-CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final latTo = bounds.north.clamp(-CoordinateGridGeometry.maxLatitude,
        CoordinateGridGeometry.maxLatitude);
    final latSpan = (latTo - latFrom).abs();
    final lngSpan = _visibleLongitudeSpanDegrees(bounds.west, bounds.east);
    final centerLongitude = camera.center.longitude;

    final lines = CoordinateGridLines.build(
      south: latFrom - latSpan * 0.05,
      north: latTo + latSpan * 0.05,
      west: centerLongitude - lngSpan / 2 - spec.lngStepDegrees,
      east: centerLongitude + lngSpan / 2 + spec.lngStepDegrees,
      spec: spec,
      maxLines: maxLines,
    );
    if (lines.latitudes.isEmpty && lines.longitudes.isEmpty) return;

    final worldShift = _worldShift();
    final halo = Paint()
      ..color = haloColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final stroke = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final latLow = _clampLatitude(
        lines.latitudes.isEmpty ? latFrom : latFrom - latSpan * 0.05);
    final latHigh = _clampLatitude(
        lines.latitudes.isEmpty ? latTo : latTo + latSpan * 0.05);
    final westEdge = centerLongitude - lngSpan / 2 - spec.lngStepDegrees;
    final eastEdge = centerLongitude + lngSpan / 2 + spec.lngStepDegrees;

    for (final latitude in lines.latitudes) {
      final a = _project(latitude, westEdge, centerLongitude, worldShift);
      final b = _project(latitude, eastEdge, centerLongitude, worldShift);
      canvas.drawLine(a, b, halo);
      canvas.drawLine(a, b, stroke);
    }
    for (final longitude in lines.longitudes) {
      final north = _project(latHigh, longitude, centerLongitude, worldShift);
      final south = _project(latLow, longitude, centerLongitude, worldShift);
      canvas.drawLine(south, north, halo);
      canvas.drawLine(south, north, stroke);
    }

    _drawLabels(
      canvas: canvas,
      size: size,
      lines: lines,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      latSpan: latSpan,
      lngSpan: lngSpan,
      worldShift: worldShift,
    );
    _drawLegend(canvas, size, spec, centerLatitude, centerLongitude);
  }

  /// Ширина видимой области в градусах долготы с учётом переноса мира
  /// (`Epsg3857.replicatesWorldLongitude`).
  double _visibleLongitudeSpanDegrees(double west, double east) {
    final worldWidth = camera.getWorldWidthAtZoom();
    if (worldWidth <= 0) {
      return (east - west).abs().clamp(0.0, 360.0);
    }
    return (360.0 * camera.size.width / worldWidth).clamp(0.0, 360.0);
  }

  /// Экранный вектор сдвига на 360° долготы (учитывает поворот карты),
  /// поэтому линиям можно задавать «развёрнутую» долготу за пределами ±180°.
  Offset _worldShift() {
    final zero = camera.latLngToScreenOffset(const LatLng(0, 0));
    final half = camera.latLngToScreenOffset(const LatLng(0, 180));
    return (half - zero) * 2;
  }

  Offset _project(
    double latitude,
    double unwrappedLongitude,
    double centerLongitude,
    Offset worldShift,
  ) {
    final wrapped = CoordinateGridGeometry.wrapLongitude(unwrappedLongitude);
    final copies = ((unwrappedLongitude - wrapped) / 360).round();
    final base = camera.latLngToScreenOffset(LatLng(latitude, wrapped));
    return copies == 0 ? base : base + worldShift * copies.toDouble();
  }

  void _drawLabels({
    required Canvas canvas,
    required Size size,
    required CoordinateGridLines lines,
    required double centerLatitude,
    required double centerLongitude,
    required double latSpan,
    required double lngSpan,
    required Offset worldShift,
  }) {
    final inset = math.min(28.0, size.shortestSide / 4);
    final viewport =
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(inset);
    final latDecimals =
        CoordinateGridGeometry.decimalsForStep(lines.latStepDegrees);
    final lngDecimals =
        CoordinateGridGeometry.decimalsForStep(lines.lngStepDegrees);

    // Подпись ставим в «видимой» точке линии: при повороте карты заранее
    // выбранная широта/долгота может оказаться вне экрана.
    final latCandidates = <double>[
      _clampLatitude(centerLatitude - latSpan * _backingCoverage),
      _clampLatitude(centerLatitude),
      _clampLatitude(centerLatitude + latSpan * _backingCoverage),
    ];
    for (final longitude in lines.longitudes) {
      final point = _firstVisible(
          latCandidates, longitude, centerLongitude, worldShift, viewport);
      if (point == null) continue;
      final value = CoordinateGridGeometry.wrapLongitude(longitude);
      final text =
          '${value.abs().toStringAsFixed(lngDecimals)}°${value >= 0 ? 'E' : 'W'}';
      _drawText(canvas, text, point + const Offset(0, -10));
    }

    final lngCandidates = <double>[
      centerLongitude - lngSpan * _backingCoverage,
      centerLongitude,
      centerLongitude + lngSpan * _backingCoverage,
    ];
    for (final latitude in lines.latitudes) {
      for (final longitude in lngCandidates) {
        final point =
            _project(latitude, longitude, centerLongitude, worldShift);
        if (!viewport.contains(point)) continue;
        final text =
            '${latitude.abs().toStringAsFixed(latDecimals)}°${latitude >= 0 ? 'N' : 'S'}';
        _drawText(canvas, text, point + const Offset(0, -10));
        break;
      }
    }
  }

  Offset? _firstVisible(
    List<double> latitudeCandidates,
    double longitude,
    double centerLongitude,
    Offset worldShift,
    Rect viewport,
  ) {
    for (final latitude in latitudeCandidates) {
      final point = _project(latitude, longitude, centerLongitude, worldShift);
      if (viewport.contains(point)) return point;
    }
    return null;
  }

  static double _clampLatitude(double latitude) => latitude.clamp(
      -CoordinateGridGeometry.maxLatitude, CoordinateGridGeometry.maxLatitude);

  void _drawLegend(
    Canvas canvas,
    Size size,
    CoordinateGridSpec spec,
    double centerLatitude,
    double centerLongitude,
  ) {
    final step = CoordinateGridGeometry.formatStep(
      spec.stepMeters,
      spec.metricUnits,
    );
    final coordinates =
        '${centerLatitude.abs().toStringAsFixed(4)}°${centerLatitude >= 0 ? 'N' : 'S'}  '
        '${centerLongitude.abs().toStringAsFixed(4)}°${centerLongitude >= 0 ? 'E' : 'W'}';
    final text = 'сетка $step  ·  $coordinates';

    final painter = _textPainter(text, Colors.white);
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
    final background = Rect.fromLTWH(
      8,
      size.height - painter.height - 8 - padding.vertical,
      painter.width + padding.horizontal,
      painter.height + padding.vertical,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(4)),
      Paint()..color = const Color(0xCC11161A),
    );
    painter.paint(
      canvas,
      Offset(background.left + padding.left, background.top + padding.top),
    );
  }

  void _drawText(Canvas canvas, String text, Offset center) {
    final halo = _textPainter(
      text,
      Colors.white,
      strokeWidth: 3,
    );
    final main = _textPainter(text, labelColor);
    final offset = center - Offset(main.width / 2, main.height / 2);
    halo.paint(canvas, offset);
    main.paint(canvas, offset);
  }

  TextPainter _textPainter(String text, Color color, {double? strokeWidth}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: strokeWidth == null ? color : null,
          foreground: strokeWidth == null
              ? null
              : (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..color = color),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant CoordinateGridPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.metricUnits != metricUnits ||
      oldDelegate.targetSpacingPixels != targetSpacingPixels ||
      oldDelegate.maxLines != maxLines ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelColor != labelColor;
}
