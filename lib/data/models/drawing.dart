import 'dart:convert';
import 'package:latlong2/latlong.dart';

class Drawing {
  final int? id;
  final String name;
  final String? description;
  final String type; // 'line' or 'polygon'
  final String category; // 'drawing' or 'measurement'
  final List<LatLng> points;

  /// Индексы в [points], с которых начинается новый независимый штрих.
  /// Пустой список (по умолчанию) — одна непрерывная линия.
  /// Обратно совместимо: старые записи без разрывов читаются как обычно.
  final List<int> segmentBreaks;
  final int color; // ARGB integer
  final double strokeWidth;
  final double fillOpacity;
  final bool visible;
  final DateTime createdAt;

  Drawing({
    this.id,
    required this.name,
    this.description,
    required this.type,
    this.category = 'drawing',
    required this.points,
    this.segmentBreaks = const <int>[],
    required this.color,
    this.strokeWidth = 3.0,
    this.fillOpacity = 0.5,
    this.visible = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Есть ли разрывы между штрихами.
  bool get hasSegments => _normalizedBreaks.isNotEmpty;

  /// Готовые штрихи, восстановленные из [points] и [segmentBreaks].
  /// Для непрерывной линии возвращает один элемент — [points].
  List<List<LatLng>> get segments {
    final breaks = _normalizedBreaks;
    if (breaks.isEmpty) return <List<LatLng>>[points];
    // Первый штрих всегда начинается с индекса 0.
    final starts = <int>[0, ...breaks];
    final result = <List<LatLng>>[];
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = index + 1 < starts.length ? starts[index + 1] : points.length;
      result.add(points.sublist(start, end));
    }
    return result;
  }

  /// Корректные, отсортированные, дедуплицированные и обрезанные по границам
  /// [points] индексы разрывов.
  List<int> get _normalizedBreaks {
    if (segmentBreaks.isEmpty || points.isEmpty) return const <int>[];
    final cleaned = <int>{};
    for (final start in segmentBreaks) {
      if (start <= 0 || start >= points.length) continue;
      cleaned.add(start);
    }
    final sorted = cleaned.toList()..sort();
    return sorted;
  }

  Drawing copyWith({
    int? id,
    String? name,
    String? description,
    String? type,
    String? category,
    List<LatLng>? points,
    List<int>? segmentBreaks,
    int? color,
    double? strokeWidth,
    double? fillOpacity,
    bool? visible,
    DateTime? createdAt,
  }) {
    return Drawing(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      category: category ?? this.category,
      points: points ?? this.points,
      segmentBreaks: segmentBreaks ?? this.segmentBreaks,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      visible: visible ?? this.visible,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final isPolygon = type == 'polygon';
    final coordinates =
        points.map((p) => [p.longitude, p.latitude]).toList(growable: false);
    final isClosed = coordinates.length > 1 &&
        coordinates.first[0] == coordinates.last[0] &&
        coordinates.first[1] == coordinates.last[1];
    final geojson = jsonEncode({
      'type': 'Feature',
      'properties': {'name': name, 'category': category},
      'geometry': {
        'type': isPolygon ? 'Polygon' : 'LineString',
        'coordinates': isPolygon
            ? [
                [
                  ...coordinates,
                  if (coordinates.isNotEmpty && !isClosed) coordinates.first,
                ]
              ]
            : coordinates,
      },
    });
    final breaks = _normalizedBreaks;
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      'category': category,
      // Обратно совместимый формат: одиночная линия пишется как раньше
      // (массив точек), разрывы — объектом с 'points' и 'segments'.
      // Колонка points_json остаётся TEXT, миграция БД не требуется.
      'points_json': jsonEncode(
        breaks.isEmpty
            ? points.map((p) => [p.latitude, p.longitude]).toList()
            : <String, dynamic>{
                'points': points
                    .map((p) => [p.latitude, p.longitude])
                    .toList(growable: false),
                'segments': breaks,
              },
      ),
      'geojson': geojson,
      'color': color,
      'stroke_width': strokeWidth,
      'fill_opacity': fillOpacity,
      'visible': visible ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Drawing.fromMap(Map<String, dynamic> map) {
    final dynamic decoded = jsonDecode(map['points_json'] as String);

    // Поддержка старого формата (массив [lat, lng]) и нового (объект
    // с 'points' и опциональным 'segments').
    final List<dynamic> rawPoints;
    final List<int> breaks = <int>[];
    if (decoded is List) {
      rawPoints = decoded;
    } else if (decoded is Map) {
      final raw = decoded['points'];
      rawPoints = raw is List ? raw : const <dynamic>[];
      final rawBreaks = decoded['segments'];
      if (rawBreaks is List) {
        for (final value in rawBreaks) {
          if (value is num) breaks.add(value.toInt());
        }
      }
    } else {
      rawPoints = const <dynamic>[];
    }

    return Drawing(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      type: map['type'] as String? ?? 'line',
      category: map['category'] as String? ?? 'drawing',
      points: rawPoints.map((p) {
        final List<dynamic> coords = p as List<dynamic>;
        return LatLng(
          (coords[0] as num).toDouble(),
          (coords[1] as num).toDouble(),
        );
      }).toList(),
      segmentBreaks: breaks,
      color: map['color'] as int,
      strokeWidth: (map['stroke_width'] as num).toDouble(),
      fillOpacity: (map['fill_opacity'] as num? ?? 0.5).toDouble(),
      visible: (map['visible'] as num? ?? 1) != 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
