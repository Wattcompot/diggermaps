import 'dart:convert';
import 'package:latlong2/latlong.dart';

class Drawing {
  final int? id;
  final String name;
  final String? description;
  final String type; // 'line' or 'polygon'
  final String category; // 'drawing' or 'measurement'
  final List<LatLng> points;
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
    required this.color,
    this.strokeWidth = 3.0,
    this.fillOpacity = 0.5,
    this.visible = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Drawing copyWith({
    int? id,
    String? name,
    String? description,
    String? type,
    String? category,
    List<LatLng>? points,
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
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      'category': category,
      'points_json': jsonEncode(
        points.map((p) => [p.latitude, p.longitude]).toList(),
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
    final List<dynamic> decoded = jsonDecode(map['points_json'] as String);
    return Drawing(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      type: map['type'] as String? ?? 'line',
      category: map['category'] as String? ?? 'drawing',
      points: decoded.map((p) {
        final List<dynamic> coords = p as List<dynamic>;
        return LatLng(
          (coords[0] as num).toDouble(),
          (coords[1] as num).toDouble(),
        );
      }).toList(),
      color: map['color'] as int,
      strokeWidth: (map['stroke_width'] as num).toDouble(),
      fillOpacity: (map['fill_opacity'] as num? ?? 0.5).toDouble(),
      visible: (map['visible'] as num? ?? 1) != 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
