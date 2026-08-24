import 'package:latlong2/latlong.dart';

class UserMarker {
  final int? id;
  final String name;
  final String? description;
  final double lat;
  final double lng;
  final String colorHex;
  final String shape;
  final double size;
  final String group;
  final bool visible;
  final DateTime createdAt;

  UserMarker({
    this.id,
    required this.name,
    this.description,
    required this.lat,
    required this.lng,
    required this.colorHex,
    this.shape = 'pin',
    this.size = 42,
    this.group = 'Общее',
    this.visible = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Совместимые геттеры
  String get title => name;
  LatLng get point => LatLng(lat, lng);
  String get color => colorHex;

  UserMarker copyWith({
    int? id,
    String? name,
    String? description,
    double? lat,
    double? lng,
    String? colorHex,
    String? shape,
    double? size,
    String? group,
    bool? visible,
    DateTime? createdAt,
  }) {
    return UserMarker(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      colorHex: colorHex ?? this.colorHex,
      shape: shape ?? this.shape,
      size: size ?? this.size,
      group: group ?? this.group,
      visible: visible ?? this.visible,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'lat': lat,
      'lng': lng,
      'color_hex': colorHex,
      'marker_shape': shape,
      'marker_size': size,
      'marker_group': group,
      'visible': visible ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory UserMarker.fromMap(Map<String, dynamic> map) {
    final createdAtValue = map['created_at'] ?? map['createdAt'];
    return UserMarker(
      id: map['id'] as int?,
      name: map['name'] ?? map['title'] ?? '',
      description: (map['description'] ?? map['desc']) as String?,
      lat: (map['lat'] ?? map['latitude'] as num).toDouble(),
      lng: (map['lng'] ?? map['longitude'] as num).toDouble(),
      colorHex: map['color_hex'] ?? map['color'] ?? '#A67B5B',
      shape: (map['marker_shape'] ?? map['icon']) as String? ?? 'pin',
      size: (map['marker_size'] as num?)?.toDouble() ?? 42,
      group: (map['marker_group'] ?? map['group']) as String? ?? 'Общее',
      visible: (map['visible'] as num? ?? 1) != 0,
      createdAt: createdAtValue is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAtValue)
          : DateTime.tryParse(createdAtValue?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
