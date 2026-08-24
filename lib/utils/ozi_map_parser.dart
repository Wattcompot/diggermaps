import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// =============================================================================
// OziMapParser  –  парсер калибровочных файлов OziExplorer (.map)
// =============================================================================
///
/// Поддерживает форматы MMPLL (географические координаты) и MMPXY
/// (проекционные координаты). Извлекает:
///  - путь к растровому изображению (rasterPath),
///  - размеры изображения (imageWidth / imageHeight),
///  - точки калибровки (Point01 .. PointNN, MMPLL/MMPXY),
///  - границы bounding-box (bounds JSON).
///
/// Для файлов в кодировке Windows-1251 делает best-effort декодирование
/// через [allowMalformed] – некорректные байты пропускаются.
// -----------------------------------------------------------------------------

/// Результат парсинга одного Ozi .map файла.
@immutable
class OziMapParseResult {
  /// Путь к растровому изображению (вторая / третья строка файла, либо
  /// явная строка "Image File,").
  final String? rasterPath;

  /// Ширина изображения (из IWH или Image Width/Height).
  final int imageWidth;

  /// Высота изображения (из IWH или Image Width/Height).
  final int imageHeight;

  /// Тип калибровки: 'MMPLL' или 'MMPXY'.
  final String calibrationType;

  /// Название проекции (если указано).
  final String? projection;

  /// Название датума (если указано).
  final String? datum;

  /// Опорные точки калибровки (пиксель → geo).
  final List<OziCalibrationPoint> points;

  const OziMapParseResult({
    this.rasterPath,
    this.imageWidth = 1,
    this.imageHeight = 1,
    this.calibrationType = 'MMPLL',
    this.projection,
    this.datum,
    this.points = const [],
  });

  // --------------------------------------------------------------------------
  // JSON helpers
  // --------------------------------------------------------------------------

  /// Возвращает массив опорных точек в виде JSON-строки:
  /// ```json
  /// [{"pixelX":100,"pixelY":200,"lat":55.5,"lng":37.6}, ...]
  /// ```
  String? get calibrationPointsJson {
    if (points.isEmpty) return null;
    final list = points
        .map((p) => {
              'pixelX': p.pixelX,
              'pixelY': p.pixelY,
              'lat': p.lat,
              'lng': p.lng,
            })
        .toList(growable: false);
    return jsonEncode(list);
  }

  /// Возвращает bounding-box всего растра как JSON-строку:
  /// ```json
  /// {"minLat":...,"maxLat":...,"minLng":...,"maxLng":...}
  /// ```
  ///
  /// При трёх и более независимых точках координаты углов экстраполируются
  /// аффинным преобразованием. Это важно, когда точки калибровки лежат внутри
  /// изображения. Для карты через антимеридиан `minLng` может быть больше
  /// `maxLng` (например, 179 и -179).
  String? get boundsJson {
    final bounds = boundsAsMap;
    return bounds == null ? null : jsonEncode(bounds);
  }

  /// Bounding-box как Dart [Map] (удобно для прямого использования).
  Map<String, double>? get boundsAsMap {
    if (points.isEmpty) return null;

    final latCoefficients =
        _fitAffine(points.map((point) => point.lat).toList());
    final referenceLongitude = points.first.lng;
    final unwrappedLongitudes = points
        .map((point) => _unwrapLongitude(point.lng, referenceLongitude))
        .toList(growable: false);
    final lngCoefficients = _fitAffine(unwrappedLongitudes);

    late final List<double> latitudes;
    late final List<double> longitudes;
    if (latCoefficients != null && lngCoefficients != null) {
      const corners = <(double, double)>[
        (0, 0),
        (1, 0),
        (0, 1),
        (1, 1),
      ];
      latitudes = corners
          .map((corner) => _applyAffine(latCoefficients, corner.$1, corner.$2))
          .toList(growable: false);
      longitudes = corners
          .map((corner) => _applyAffine(lngCoefficients, corner.$1, corner.$2))
          .toList(growable: false);
    } else {
      latitudes = points.map((point) => point.lat).toList(growable: false);
      longitudes = unwrappedLongitudes;
    }

    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final westUnwrapped = longitudes.reduce((a, b) => a < b ? a : b);
    final eastUnwrapped = longitudes.reduce((a, b) => a > b ? a : b);
    return {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLng': _normalizeLongitude(westUnwrapped),
      'maxLng': _normalizeLongitude(eastUnwrapped),
    };
  }

  List<double>? _fitAffine(List<double> values) {
    if (points.length < 3 || values.length != points.length) return null;
    final width = imageWidth.toDouble();
    final height = imageHeight.toDouble();
    if (width <= 0 || height <= 0) return null;

    double suu = 0, suv = 0, svv = 0, su = 0, sv = 0;
    double sut = 0, svt = 0, st = 0;
    for (var index = 0; index < points.length; index++) {
      final u = points[index].pixelX / width;
      final v = points[index].pixelY / height;
      final target = values[index];
      suu += u * u;
      suv += u * v;
      svv += v * v;
      su += u;
      sv += v;
      sut += u * target;
      svt += v * target;
      st += target;
    }

    return _solve3x3([
      [suu, suv, su, sut],
      [suv, svv, sv, svt],
      [su, sv, points.length.toDouble(), st],
    ]);
  }

  static List<double>? _solve3x3(List<List<double>> matrix) {
    for (var column = 0; column < 3; column++) {
      var pivot = column;
      for (var row = column + 1; row < 3; row++) {
        if (matrix[row][column].abs() > matrix[pivot][column].abs()) {
          pivot = row;
        }
      }
      if (matrix[pivot][column].abs() < 1e-12) return null;
      if (pivot != column) {
        final temporary = matrix[column];
        matrix[column] = matrix[pivot];
        matrix[pivot] = temporary;
      }

      final divisor = matrix[column][column];
      for (var item = column; item < 4; item++) {
        matrix[column][item] /= divisor;
      }
      for (var row = 0; row < 3; row++) {
        if (row == column) continue;
        final factor = matrix[row][column];
        for (var item = column; item < 4; item++) {
          matrix[row][item] -= factor * matrix[column][item];
        }
      }
    }
    return [matrix[0][3], matrix[1][3], matrix[2][3]];
  }

  static double _applyAffine(List<double> coefficients, double x, double y) =>
      coefficients[0] * x + coefficients[1] * y + coefficients[2];

  static double _unwrapLongitude(double longitude, double reference) {
    var result = longitude;
    while (result - reference > 180) {
      result -= 360;
    }
    while (result - reference < -180) {
      result += 360;
    }
    return result;
  }

  static double _normalizeLongitude(double longitude) {
    final normalized = (longitude + 180) % 360;
    return (normalized < 0 ? normalized + 360 : normalized) - 180;
  }

  @override
  String toString() =>
      'OziMapParseResult(raster: $rasterPath, size: ${imageWidth}x$imageHeight, '
      'type: $calibrationType, points: ${points.length})';
}

/// Внутреннее представление одной опорной точки.
class OziCalibrationPoint {
  final int pixelX;
  final int pixelY;
  final double lat;
  final double lng;

  const OziCalibrationPoint({
    required this.pixelX,
    required this.pixelY,
    required this.lat,
    required this.lng,
  });

  @override
  String toString() =>
      'OziCalibrationPoint(pixel: $pixelX,$pixelY  geo: $lat,$lng)';
}

// =============================================================================
// Парсер
// =============================================================================

class OziMapParser {
  OziMapParser._();

  /// Читает .map файл с диска. Для файлов в кодировке Windows-1251 делает
  /// best-effort декодирование (allowMalformed).
  static Future<OziMapParseResult> parseFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return parseBytes(bytes);
  }

  /// Парсит содержимое .map файла, переданное в виде строки (UTF-8).
  static OziMapParseResult parseString(String content) {
    final lines = const LineSplitter().convert(content);
    return _parseLines(lines);
  }

  /// Парсит содержимое .map файла из байтов. Пытается UTF-8, при неудаче –
  /// Windows-1251 (best-effort с allowMalformed).
  static OziMapParseResult parseBytes(List<int> bytes) {
    // Сначала пробуем UTF-8.
    try {
      final content = utf8.decode(bytes);
      return parseString(content);
    } catch (_) {
      // Пытаемся Windows-1251 с allowMalformed.
      final content = _decodeWindows1251(bytes);
      return parseString(content);
    }
  }

  // --------------------------------------------------------------------------
  // Основной парсинг строк
  // --------------------------------------------------------------------------

  static OziMapParseResult _parseLines(List<String> lines) {
    String? rasterPath;
    int imageWidth = 1;
    int imageHeight = 1;
    String calibrationType = 'MMPLL';
    String? projection;
    String? datum;

    // Временные карты для MMPXY/MMPLL записей.
    final Map<String, (int x, int y)> pixelMap = {};
    final Map<String, (double lat, double lng)> geoMap = {};
    final List<OziCalibrationPoint> points = [];

    // Флаг: нашли ли мы rasterPath через Image File.
    bool foundImageFile = false;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;

      // ---- raster path -------------------------------------------------------
      // Line 0: header.  Line 1: map name.  Line 2: raster file path.
      // Also try line 1 as a fallback (some .map files skip the name).
      // We let line 2 unconditionally overwrite any candidate from line 1.
      if (!foundImageFile && i <= 2) {
        final isCandidate = !trimmed.startsWith('OziExplorer') &&
            !trimmed.startsWith('WGS ') &&
            !trimmed.startsWith('Reserved') &&
            !trimmed.contains(',') &&
            trimmed.isNotEmpty;
        if (isCandidate) {
          rasterPath = trimmed; // line 2 overwrites line 1 naturally.
        }
      }

      // Явная строка "Image File,".
      if (!foundImageFile &&
          (trimmed.toLowerCase().startsWith('image file,') ||
              trimmed.toLowerCase().startsWith('image file='))) {
        rasterPath = trimmed.substring(trimmed.indexOf(',') + 1).trim();
        if (rasterPath.isEmpty) rasterPath = null;
        foundImageFile = true;
      }

      // ---- type --------------------------------------------------------------
      if (trimmed == 'MMPLL' || trimmed == 'MMPXY') {
        calibrationType = trimmed;
        continue;
      }

      // ---- projection / datum ------------------------------------------------
      if (trimmed.startsWith('Projection,')) {
        projection = trimmed.substring('Projection,'.length).trim();
        continue;
      }
      if (trimmed.startsWith('Datum,')) {
        datum = trimmed.substring('Datum,'.length).trim();
        continue;
      }

      // ---- IWH (image dimensions) --------------------------------------------
      if (trimmed.startsWith('IWH,')) {
        final afterPrefix = trimmed.substring(4);
        final parts =
            afterPrefix.split(',').map((s) => int.tryParse(s.trim())).toList();
        // "IWH,width,height" gives [w, h]; "IWH,Map Image Width/Height,w,h"
        // gives [null, w, h] — take the last two valid ints.
        final nums = <int>[];
        for (final p in parts) {
          if (p != null) nums.add(p);
        }
        if (nums.length >= 2) {
          // Последние два: ширина, потом высота.
          imageWidth = nums[nums.length - 2];
          imageHeight = nums[nums.length - 1];
        }
        continue;
      }

      // Альтернативные обозначения размеров.
      if (trimmed.toLowerCase().contains('image width') &&
          trimmed.toLowerCase().contains('image height')) {
        final parts =
            trimmed.split(',').map((s) => int.tryParse(s.trim())).toList();
        // Ищем два числа подряд.
        final nums = <int>[];
        for (final p in parts) {
          if (p != null) nums.add(p);
        }
        if (nums.length >= 2) {
          imageWidth = nums[nums.length - 2];
          imageHeight = nums[nums.length - 1];
        }
        continue;
      }

      // ---- PointNN (стандартные точки) ---------------------------------------
      if (trimmed.startsWith('Point')) {
        final parts = trimmed.split(',').map((s) => s.trim()).toList();
        if (parts.length >= 12) {
          final px = int.tryParse(parts[2]);
          final py = int.tryParse(parts[3]);
          // parts[4] = "in" (in/out ignored)
          // parts[5] = "deg" or "utm" etc.
          final latDeg = double.tryParse(parts[6]);
          final latMin = double.tryParse(parts[7]);
          // parts[8] = N/S
          final lngDeg = double.tryParse(parts[9]);
          final lngMin = double.tryParse(parts[10]);
          // parts[11] = E/W

          if (parts[5].toLowerCase() == 'deg' &&
              px != null &&
              py != null &&
              latDeg != null &&
              latMin != null &&
              lngDeg != null &&
              lngMin != null) {
            double lat = latDeg + latMin / 60.0;
            double lng = lngDeg + lngMin / 60.0;
            if (parts[8].toUpperCase() == 'S') lat = -lat;
            if (parts[11].toUpperCase() == 'W') lng = -lng;
            points.add(OziCalibrationPoint(
              pixelX: px,
              pixelY: py,
              lat: lat,
              lng: lng,
            ));
          }
        }
        continue;
      }

      // ---- MMPNUM ------------------------------------------------------------
      if (trimmed.startsWith('MMPNUM,')) continue;

      // ---- MMPXY -------------------------------------------------------------
      if (trimmed.startsWith('MMPXY,')) {
        final parts = trimmed.split(',').map((s) => s.trim()).toList();
        if (parts.length >= 4) {
          final idx = parts[1];
          final x = int.tryParse(parts[2]);
          final y = int.tryParse(parts[3]);
          if (x != null && y != null) {
            pixelMap['MMP$idx'] = (x, y);
          }
        }
        continue;
      }

      // ---- MMPLL -------------------------------------------------------------
      if (trimmed.startsWith('MMPLL,')) {
        final parts = trimmed.split(',').map((s) => s.trim()).toList();
        if (parts.length >= 4) {
          final idx = parts[1];
          final lng = double.tryParse(parts[2]);
          final lat = double.tryParse(parts[3]);
          if (lat != null && lng != null) {
            geoMap['MMP$idx'] = (lat, lng);
          }
        }
        continue;
      }

      // ---- MMx (прямые точки типа "MM, x, y, lon, lat" – устаревший формат) --
      if (trimmed.startsWith('MM') && !trimmed.startsWith('MMP')) {
        final commaIdx = trimmed.indexOf(',');
        if (commaIdx == -1) continue;
        final body = trimmed.substring(commaIdx + 1);
        final vals =
            body.split(',').map((s) => double.tryParse(s.trim())).toList();
        if (vals.length >= 4 &&
            vals[0] != null &&
            vals[1] != null &&
            vals[2] != null &&
            vals[3] != null) {
          points.add(OziCalibrationPoint(
            pixelX: vals[0]!.round(),
            pixelY: vals[1]!.round(),
            lng: vals[2]!,
            lat: vals[3]!,
          ));
        }
        continue;
      }
    }

    // Собираем точки из MMPXY + MMPLL.
    for (final entry in pixelMap.entries) {
      final geo = geoMap[entry.key];
      if (geo == null) continue;
      points.add(OziCalibrationPoint(
        pixelX: entry.value.$1,
        pixelY: entry.value.$2,
        lat: geo.$1,
        lng: geo.$2,
      ));
    }

    return OziMapParseResult(
      rasterPath: rasterPath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      calibrationType: calibrationType,
      projection: projection,
      datum: datum,
      points: points,
    );
  }

  // --------------------------------------------------------------------------
  // Windows-1251 best-effort decode
  // --------------------------------------------------------------------------

  /// Декодирует байты как Windows-1251, заменяя некорректные байты на �.
  static String _decodeWindows1251(List<int> bytes) {
    // Таблица Windows-1251 для байтов 0x80..0xFF.
    const win1251 = <int>[
      0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, // 80
      0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, // 88
      0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90
      0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, // 98
      0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, // A0
      0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407, // A8
      0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, // B0
      0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457, // B8
      0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, // C0
      0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F, // C8
      0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, // D0
      0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, // D8
      0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, // E0
      0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F, // E8
      0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, // F0
      0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, // F8
    ];

    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else {
        buf.writeCharCode(win1251[b - 0x80]);
      }
    }
    return buf.toString();
  }
}
