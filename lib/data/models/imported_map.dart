import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class ImportedMap {
  final int? id;
  final String name;

  /// Path to .map calibration file (for Ozi raster overlays).
  final String? mapFilePath;

  /// Path to the raster image or .mbtiles file.
  final String? imageFilePath;

  /// Format identifier: 'raster', 'ozf2', 'mbtiles', 'jnx', or others.
  final String format;

  /// JSON: {"minLat":..., "maxLat":..., "minLng":..., "maxLng":...}
  final String? boundsJson;

  /// JSON array of calibration points: [{"pixelX":..., "pixelY":..., "lat":..., "lng":...}]
  final String? calibrationPointsJson;

  /// Horizontal offset in degrees. Default 0.
  final double offsetX;

  /// Vertical offset in degrees. Default 0.
  final double offsetY;

  /// Layer opacity 0..1. Default 0.7.
  final double opacity;

  /// Whether the layer is visible on the map. Default true.
  final bool visible;

  final DateTime createdAt;

  const ImportedMap({
    this.id,
    required this.name,
    this.mapFilePath,
    this.imageFilePath,
    required this.format,
    this.boundsJson,
    this.calibrationPointsJson,
    this.offsetX = 0,
    this.offsetY = 0,
    this.opacity = 0.7,
    this.visible = true,
    required this.createdAt,
  });

  // ---------------------------------------------------------------------------
  // Backward-compatible getters (old codeuses path / type / bounds).
  // ---------------------------------------------------------------------------

  /// Backward-compatible alias: first non-null of [mapFilePath] or [imageFilePath].
  String? get path => mapFilePath ?? imageFilePath;

  /// Backward-compatible alias for [format].
  String? get type => format;

  /// Backward-compatible alias for [boundsJson].
  String? get bounds => boundsJson;

  // ---------------------------------------------------------------------------
  // Derived helpers.
  // ---------------------------------------------------------------------------

  /// True when this row supports calibrated overlay controls.
  ///
  /// MBTiles are rendered by TileLayer, while legacy rasters are rendered by
  /// OverlayImageLayer; both use the same stored opacity and offset settings.
  bool get isRasterOverlay {
    const calibratedFormats = <String>{
      'ozi_map',
      'raster',
      'png',
      'jpg',
      'jpeg',
      'tif',
      'tiff',
      'ozf',
      'ozf2',
      'ozfx3',
      'mbtiles',
    };
    return calibratedFormats.contains(format.toLowerCase()) &&
        imageFilePath != null &&
        boundsJson != null;
  }

  /// True when this is an MBTiles source.
  bool get isMbtiles => format.toLowerCase() == 'mbtiles';

  /// Parses [boundsJson] into a [Map] with keys minLat, maxLat, minLng, maxLng.
  /// Returns `null` when bounds are missing or malformed.
  Map<String, double>? get parsedBounds {
    if (boundsJson == null || boundsJson!.isEmpty) return null;
    try {
      final map = jsonDecode(boundsJson!) as Map<String, dynamic>;
      return {
        'minLat': (map['minLat'] as num).toDouble(),
        'maxLat': (map['maxLat'] as num).toDouble(),
        'minLng': (map['minLng'] as num).toDouble(),
        'maxLng': (map['maxLng'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Serialisation helpers.
  // ---------------------------------------------------------------------------

  ImportedMap copyWith({
    int? id,
    String? name,
    String? mapFilePath,
    String? imageFilePath,
    String? format,
    String? boundsJson,
    String? calibrationPointsJson,
    double? offsetX,
    double? offsetY,
    double? opacity,
    bool? visible,
    DateTime? createdAt,
    // ignore: avoid_dynamic_calls
    bool clearMapFilePath = false,
    // ignore: avoid_dynamic_calls
    bool clearImageFilePath = false,
    // ignore: avoid_dynamic_calls
    bool clearBoundsJson = false,
    // ignore: avoid_dynamic_calls
    bool clearCalibrationPointsJson = false,
  }) {
    return ImportedMap(
      id: id ?? this.id,
      name: name ?? this.name,
      mapFilePath: clearMapFilePath ? null : (mapFilePath ?? this.mapFilePath),
      imageFilePath:
          clearImageFilePath ? null : (imageFilePath ?? this.imageFilePath),
      format: format ?? this.format,
      boundsJson: clearBoundsJson ? null : (boundsJson ?? this.boundsJson),
      calibrationPointsJson: clearCalibrationPointsJson
          ? null
          : (calibrationPointsJson ?? this.calibrationPointsJson),
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'map_file_path': mapFilePath,
      'image_file_path': imageFilePath,
      'format': format,
      'bounds_json': boundsJson,
      'calibration_points_json': calibrationPointsJson,
      'offset_x': offsetX,
      'offset_y': offsetY,
      'opacity': opacity,
      'visible': visible ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Builds an [ImportedMap] from a database row.
  ///
  /// Supports both the **new** schema (format, map_file_path, image_file_path,
  /// bounds_json, …) and the **legacy** schema (type, path, bounds) so that
  /// existing rows survive the migration transparently.
  factory ImportedMap.fromMap(Map<String, dynamic> map) {
    final rawCreatedAt = map['created_at'];
    final createdAt = rawCreatedAt is int
        ? DateTime.fromMillisecondsSinceEpoch(rawCreatedAt)
        : (rawCreatedAt is String
            ? DateTime.tryParse(rawCreatedAt) ?? DateTime.now()
            : DateTime.now());

    return ImportedMap(
      id: map['id'] as int?,
      name: (map['name'] ?? '') as String,
      mapFilePath: (map['map_file_path'] ?? map['mapFilePath']) as String?,
      imageFilePath: (map['image_file_path'] ??
          map['imageFilePath'] ??
          map['path']) as String?,
      format: (map['format'] ?? map['type'] ?? 'raster') as String,
      boundsJson:
          (map['bounds_json'] ?? map['bounds'] ?? map['boundsJson']) as String?,
      calibrationPointsJson: (map['calibration_points_json'] ??
          map['calibrationPointsJson']) as String?,
      offsetX: (map['offset_x'] as num?)?.toDouble() ?? 0,
      offsetY: (map['offset_y'] as num?)?.toDouble() ?? 0,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.7,
      visible: (map['visible'] as num? ?? 1) != 0,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportedMap &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          mapFilePath == other.mapFilePath &&
          imageFilePath == other.imageFilePath &&
          format == other.format &&
          boundsJson == other.boundsJson &&
          calibrationPointsJson == other.calibrationPointsJson &&
          offsetX == other.offsetX &&
          offsetY == other.offsetY &&
          opacity == other.opacity &&
          visible == other.visible &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        mapFilePath,
        imageFilePath,
        format,
        boundsJson,
        calibrationPointsJson,
        offsetX,
        offsetY,
        opacity,
        visible,
        createdAt,
      );

  @override
  String toString() =>
      'ImportedMap(id: $id, name: $name, format: $format, visible: $visible)';
}
