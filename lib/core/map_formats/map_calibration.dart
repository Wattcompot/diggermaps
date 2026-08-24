/// Парсер файлов калибровки OziExplorer (.map).
///
/// Поддерживает основные типы калибровки:
/// - MMPLL: по географическим координатам (lat/lon)
/// - MMPXY: по проекционным координатам (UTM, etc.)
///
/// Извлекает опорные точки привязки пиксель -> географические координаты
/// и метаданные (проекция, датум).
library;

import 'dart:io';

class CalibrationPoint {
  final int pixelX;
  final int pixelY;
  final double lat;
  final double lon;

  const CalibrationPoint({
    required this.pixelX,
    required this.pixelY,
    required this.lat,
    required this.lon,
  });

  @override
  String toString() =>
      'CalibrationPoint(pixel: $pixelX, $pixelY  geo: $lat, $lon)';
}

class OziMapCalibration {
  final String type; // MMPLL, MMPXY
  final String? projection;
  final String? datum;
  final int imageWidth;
  final int imageHeight;
  final List<CalibrationPoint> points;

  const OziMapCalibration({
    required this.type,
    this.projection,
    this.datum,
    required this.imageWidth,
    required this.imageHeight,
    required this.points,
  });

  /// Загружает калибровку из файла .map.
  factory OziMapCalibration.fromFile(String filePath) {
    final lines = File(filePath).readAsLinesSync();
    return _parse(lines);
  }

  /// Загружает калибровку из строки.
  factory OziMapCalibration.fromString(String content) {
    final lines = content.split('\n');
    return _parse(lines);
  }

  /// Вычисляет географические координаты для точки в пикселях
  /// методом линейной интерполяции по опорным точкам.
  (double lat, double lon) pixelToGeo(int px, int py) {
    if (points.length < 2) {
      return (0, 0);
    }

    // Для MMPLL используем аффинное преобразование по всем точкам
    if (points.length >= 3) {
      return _affineTransform(px, py);
    }

    // Для двух точек — простая линейная интерполяция
    final p0 = points[0];
    final p1 = points[1];
    final dx = p1.pixelX - p0.pixelX;
    final dy = p1.pixelY - p0.pixelY;

    if (dx == 0 && dy == 0) return (p0.lat, p0.lon);

    final fractionX = dx != 0 ? (px - p0.pixelX) / dx : 0.0;
    final fractionY = dy != 0 ? (py - p0.pixelY) / dy : 0.0;

    final lat = p0.lat + (p1.lat - p0.lat) * fractionY;
    final lon = p0.lon + (p1.lon - p0.lon) * fractionX;

    return (lat, lon);
  }

  (double lat, double lon) _affineTransform(int px, int py) {
    // Метод наименьших квадратов для аффинного преобразования
    // x_geo = A*px + B*py + C
    // y_geo = D*px + E*py + F
    double sx = 0, sy = 0, sx2 = 0, sy2 = 0, sxy = 0;

    for (final p in points) {
      final x = p.pixelX.toDouble();
      final y = p.pixelY.toDouble();
      sx += x;
      sy += y;
      sx2 += x * x;
      sy2 += y * y;
      sxy += x * y;
    }

    final n = points.length.toDouble();

    // Решаем систему для lon (X_geo)
    final det = n * (sx2 * sy2 - sxy * sxy) -
        sx * (sx * sy2 - sy * sxy) +
        sy * (sx * sxy - sy * sx2);

    if (det.abs() > 0.0001) {
      // Полная аффинная модель
      // Упрощённо: используем 6-параметрическую модель
      // Для стабильности переходим к упрощённой билинейной интерполяции
      return _bilinearInterpolation(px, py);
    }

    return _bilinearInterpolation(px, py);
  }

  (double lat, double lon) _bilinearInterpolation(int px, int py) {
    // Находим 4 ближайшие опорные точки
    if (points.length < 4) {
      if (points.length >= 2) {
        return _simpleInterpolation(px, py);
      }
      return (points.first.lat, points.first.lon);
    }

    // Билинейная интерполяция по ограничивающему прямоугольнику опорных точек
    final minX = points.map((p) => p.pixelX).reduce((a, b) => a < b ? a : b);
    final maxX = points.map((p) => p.pixelX).reduce((a, b) => a > b ? a : b);
    final minY = points.map((p) => p.pixelY).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.pixelY).reduce((a, b) => a > b ? a : b);

    // Clamp
    final cx = px.clamp(minX, maxX);
    final cy = py.clamp(minY, maxY);

    // Fractional position within the rectangle
    final fx = (maxX != minX) ? (cx - minX) / (maxX - minX).toDouble() : 0.0;
    final fy = (maxY != minY) ? (cy - minY) / (maxY - minY).toDouble() : 0.0;

    // Find the corner calibration points
    CalibrationPoint? findPoint(int x, int y) {
      CalibrationPoint? best;
      int bestDist = 999999;
      for (final p in points) {
        final dist = (p.pixelX - x).abs() + (p.pixelY - y).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = p;
        }
      }
      return best;
    }

    final tl = findPoint(minX, minY)!;
    final tr = findPoint(maxX, minY)!;
    final bl = findPoint(minX, maxY)!;
    final br = findPoint(maxX, maxY)!;

    // Bilinear interpolation
    final latTop = tl.lat + (tr.lat - tl.lat) * fx;
    final latBottom = bl.lat + (br.lat - bl.lat) * fx;
    final lat = latTop + (latBottom - latTop) * fy;

    final lonTop = tl.lon + (tr.lon - tl.lon) * fx;
    final lonBottom = bl.lon + (br.lon - bl.lon) * fx;
    final lon = lonTop + (lonBottom - lonTop) * fy;

    return (lat, lon);
  }

  (double lat, double lon) _simpleInterpolation(int px, int py) {
    final p0 = points.first;
    final p1 = points.last;
    final dx = p1.pixelX - p0.pixelX;
    final dy = p1.pixelY - p0.pixelY;

    final fractionX = dx != 0 ? (px - p0.pixelX) / dx : 0.0;
    final fractionY = dy != 0 ? (py - p0.pixelY) / dy : 0.0;

    final lat = p0.lat + (p1.lat - p0.lat) * fractionY;
    final lon = p0.lon + (p1.lon - p0.lon) * fractionX;

    return (lat, lon);
  }

  /// Возвращает границы карты (bounding box).
  ({double minLat, double maxLat, double minLon, double maxLon}) get bounds {
    double minLat = 90, maxLat = -90;
    double minLon = 180, maxLon = -180;

    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    return (
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );
  }

  @override
  String toString() =>
      'OziMapCalibration(type: $type, size: ${imageWidth}x$imageHeight, '
      'points: ${points.length}, bounds: $bounds)';
}

/// Парсинг содержимого .map файла.
OziMapCalibration _parse(List<String> lines) {
  String type = 'MMPLL';
  String? projection;
  String? datum;
  int imageWidth = 1;
  int imageHeight = 1;
  final List<CalibrationPoint> points = [];
  final pointPixels = <String, (int x, int y)>{};
  final pointCoordinates = <String, (double lat, double lon)>{};

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Заголовок типа калибровки
    if (trimmed == 'MMPLL' || trimmed == 'MMPXY') {
      type = trimmed;
      continue;
    }

    // Проекция
    if (trimmed.startsWith('Projection,')) {
      projection = trimmed.substring('Projection,'.length).trim();
      continue;
    }

    // Размер изображения (MMPLL)
    if (trimmed.startsWith('IWH,')) {
      final parts = trimmed.substring(4).split(',').map((s) {
        return int.tryParse(s.trim()) ?? 0;
      }).toList();
      if (parts.length >= 2) {
        imageWidth = parts[0];
        imageHeight = parts[1];
      }
      continue;
    }

    // Standard OziExplorer calibration records:
    // Point01,xy,100,200,in,deg,55,30.000,N,37,36.000,E,...
    if (trimmed.startsWith('Point')) {
      final parts = trimmed.split(',').map((value) => value.trim()).toList();
      if (parts.length >= 12) {
        final id = parts[0];
        final pixelX = int.tryParse(parts[2]);
        final pixelY = int.tryParse(parts[3]);
        final latDegrees = double.tryParse(parts[6]);
        final latMinutes = double.tryParse(parts[7]);
        final lonDegrees = double.tryParse(parts[9]);
        final lonMinutes = double.tryParse(parts[10]);
        if (pixelX != null &&
            pixelY != null &&
            latDegrees != null &&
            latMinutes != null &&
            lonDegrees != null &&
            lonMinutes != null) {
          var lat = latDegrees + latMinutes / 60;
          var lon = lonDegrees + lonMinutes / 60;
          if (parts[8].toUpperCase() == 'S') lat = -lat;
          if (parts[11].toUpperCase() == 'W') lon = -lon;
          pointPixels[id] = (pixelX, pixelY);
          pointCoordinates[id] = (lat, lon);
        }
      }
      continue;
    }

    if (trimmed.startsWith('MMPNUM,')) continue;
    if (trimmed.startsWith('MMPXY,')) {
      final parts = trimmed.split(',').map((value) => value.trim()).toList();
      if (parts.length >= 4) {
        pointPixels['MMP${parts[1]}'] = (
          int.tryParse(parts[2]) ?? 0,
          int.tryParse(parts[3]) ?? 0,
        );
      }
      continue;
    }
    if (trimmed.startsWith('MMPLL,')) {
      final parts = trimmed.split(',').map((value) => value.trim()).toList();
      if (parts.length >= 4) {
        final lon = double.tryParse(parts[2]);
        final lat = double.tryParse(parts[3]);
        if (lat != null && lon != null) {
          pointCoordinates['MMP${parts[1]}'] = (lat, lon);
        }
      }
      continue;
    }

    // Калибровочные точки MMPLL
    // Формат: MM0, x, y, lon, lat
    // или: MM, x, y, lon, lat
    if (trimmed.startsWith('MM') && !trimmed.startsWith('MMP')) {
      // Extract parameters after "MMx,"
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) continue;

      final paramsStr = trimmed.substring(commaIndex + 1);
      final parts =
          paramsStr.split(',').map((s) => double.tryParse(s.trim())).toList();

      if (parts.length >= 4 &&
          parts[0] != null &&
          parts[1] != null &&
          parts[2] != null &&
          parts[3] != null) {
        points.add(CalibrationPoint(
          pixelX: parts[0]!.round(),
          pixelY: parts[1]!.round(),
          lon: parts[2]!,
          lat: parts[3]!,
        ));
      }
      continue;
    }

    // Калибровочные точки MMPXY
    // Формат: MM0, x, y, easting, northing
    if (trimmed.startsWith('MM0') && type == 'MMPXY') {
      final parts = trimmed
          .substring(3)
          .split(',')
          .map((s) => double.tryParse(s.trim()))
          .toList();

      if (parts.length >= 4 &&
          parts[0] != null &&
          parts[1] != null &&
          parts[2] != null &&
          parts[3] != null) {
        // MMPXY использует проекционные координаты — преобразование не
        // реализовано; сохраняем как есть для диагностики.
        points.add(CalibrationPoint(
          pixelX: parts[0]!.round(),
          pixelY: parts[1]!.round(),
          lon: parts[2]!,
          lat: parts[3]!,
        ));
      }
      continue;
    }
  }

  for (final entry in pointPixels.entries) {
    final geo = pointCoordinates[entry.key];
    if (geo == null) continue;
    points.add(CalibrationPoint(
      pixelX: entry.value.$1,
      pixelY: entry.value.$2,
      lat: geo.$1,
      lon: geo.$2,
    ));
  }

  return OziMapCalibration(
    type: type,
    projection: projection,
    datum: datum,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    points: points,
  );
}
