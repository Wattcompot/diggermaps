import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class MeasurementUtils {
  static const double earthRadius = 6371000.0; // в метрах

  /// Расстояние Гаверсинуса между двумя точками (точность double)
  static double haversineDistance(LatLng p1, LatLng p2) {
    final lat1 = p1.latitude * math.pi / 180.0;
    final lon1 = p1.longitude * math.pi / 180.0;
    final lat2 = p2.latitude * math.pi / 180.0;
    final lon2 = p2.longitude * math.pi / 180.0;

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  static double calculateDistance(LatLng p1, LatLng p2) =>
      haversineDistance(p1, p2);

  static bool isPointInDrawing(LatLng point, dynamic drawing) {
    // Упрощенный hit-test: расстояние до ближайшей точки меньше порога (метры)
    final points = drawing.points as List<LatLng>;
    for (final p in points) {
      if (calculateDistance(point, p) < 50) return true;
    }
    return false;
  }

  static String formatMeasurement(dynamic drawing, bool metric) {
    if (drawing.type == 'polygon') {
      return formatArea(calculateArea(drawing.points), metric: metric);
    }
    return formatDistance(totalDistance(drawing.points), metric: metric);
  }

  /// Общая длина пути
  static double totalDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += haversineDistance(points[i], points[i + 1]);
    }
    return total;
  }

  /// Площадь сферического многоугольника
  /// Точность <=1% для площадей <100 км²
  static double calculateArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;

    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      final lat1 = p1.latitude * math.pi / 180.0;
      final lon1 = p1.longitude * math.pi / 180.0;
      final lat2 = p2.latitude * math.pi / 180.0;
      final lon2 = p2.longitude * math.pi / 180.0;

      area += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    area = area * earthRadius * earthRadius / 2.0;
    return area.abs();
  }

  /// Форматирование расстояния
  /// Пороги: <1000м -> м, >=1км -> км; imperial: <1 mi -> ft, >=1 mi -> mi
  static String formatDistance(double meters, {bool metric = true}) {
    if (metric) {
      if (meters < 1000) {
        return '${meters.toStringAsFixed(1)} м';
      } else {
        return '${(meters / 1000).toStringAsFixed(1)} км';
      }
    } else {
      final miles = meters / 1609.344;
      if (miles < 1.0) {
        final feet = meters * 3.28084;
        return '${feet.toStringAsFixed(0)} ft';
      } else {
        return '${miles.toStringAsFixed(2)} mi';
      }
    }
  }

  /// Форматирование площади
  static String formatArea(double sqMeters, {bool metric = true}) {
    if (metric) {
      if (sqMeters < 10000) {
        return '${sqMeters.toStringAsFixed(0)} м²';
      } else if (sqMeters <= 1000000) {
        return '${(sqMeters / 10000).toStringAsFixed(1)} га';
      } else {
        return '${(sqMeters / 1000000).toStringAsFixed(1)} км²';
      }
    } else {
      final sqMiles = sqMeters / 2589988.11;
      if (sqMiles < 1.0) {
        final sqFeet = sqMeters * 10.7639;
        return '${sqFeet.toStringAsFixed(0)} sq ft';
      } else {
        return '${sqMiles.toStringAsFixed(2)} sq mi';
      }
    }
  }
}
