import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'marker_media.dart';

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
  final List<MarkerMedia> media;

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
    List<MarkerMedia> media = const [],
  })  : createdAt = createdAt ?? DateTime.now(),
        media = List.unmodifiable(media);

  // Совместимые геттеры
  String get title => name;
  LatLng get point => LatLng(lat, lng);
  String get color => colorHex;

  bool get hasMedia => media.isNotEmpty;
  int get photoCount => media.where((item) => item.isPhoto).length;
  int get voiceCount => media.where((item) => item.isVoice).length;
  int get videoCount => media.where((item) => item.isVideo).length;

  /// Основное фото плашки — первое добавленное.
  MarkerMedia? get primaryPhoto {
    for (final item in media) {
      if (item.isPhoto) return item;
    }
    return null;
  }

  /// Первая голосовая заметка (для компактного плеера в плашке).
  MarkerMedia? get primaryVoice {
    for (final item in media) {
      if (item.isVoice) return item;
    }
    return null;
  }

  /// Первое видео (компактный индикатор в плашке).
  MarkerMedia? get primaryVideo {
    for (final item in media) {
      if (item.isVideo) return item;
    }
    return null;
  }

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
    List<MarkerMedia>? media,
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
      media: media ?? this.media,
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
      'media_json': jsonEncode(media.map((item) => item.toMap()).toList()),
    };
  }

  /// Tolerates the legacy column names/types of both marker tables.
  static double _coordinate(dynamic primary, dynamic fallback) =>
      (primary is num
              ? primary
              : fallback is num
                  ? fallback
                  : null)
          ?.toDouble() ??
      double.tryParse('${primary ?? fallback ?? ''}') ??
      0;

  factory UserMarker.fromMap(Map<String, dynamic> map) {
    final createdAtValue = map['created_at'] ?? map['createdAt'];
    return UserMarker(
      id: map['id'] as int?,
      name: map['name'] ?? map['title'] ?? '',
      description: (map['description'] ?? map['desc']) as String?,
      lat: _coordinate(map['lat'], map['latitude']),
      lng: _coordinate(map['lng'], map['longitude']),
      colorHex: map['color_hex'] ?? map['color'] ?? '#A67B5B',
      shape: (map['marker_shape'] ?? map['icon']) as String? ?? 'pin',
      size: (map['marker_size'] as num?)?.toDouble() ?? 42,
      group: (map['marker_group'] ?? map['group']) as String? ?? 'Общее',
      visible: map['visible'] is bool
          ? map['visible'] as bool
          : (map['visible'] as num? ?? 1) != 0,
      media: MarkerMedia.decodeList(map['media_json'] ?? map['media']),
      createdAt: createdAtValue is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAtValue)
          : DateTime.tryParse(createdAtValue?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
