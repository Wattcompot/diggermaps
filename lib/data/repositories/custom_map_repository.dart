import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MapLayerType { base, overlay }

enum MapSourceType {
  network,
  mbtiles,
  sqlitedb,
  oziMap,
  ozf2,
  jnx,
  kml,
  kmz,
  gpx,
  geotiff,
  garminImg,
  birdseye,
}

class CustomMapLayer {
  const CustomMapLayer({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.maxZoom,
    this.type = MapLayerType.base,
    this.sourceType = MapSourceType.network,
    this.filePath,
    this.latitudeOffset = 0.0,
    this.longitudeOffset = 0.0,
    this.enabled = true,
    this.opacity = 0.55,
    this.isRenderable = true,
    this.validationMessage,
  });

  final String id;
  final String name;
  final String urlTemplate;
  final int maxZoom;
  final MapLayerType type;
  final MapSourceType sourceType;
  final String? filePath;
  final double latitudeOffset;
  final double longitudeOffset;
  final bool enabled;
  final double opacity;
  final bool isRenderable;
  final String? validationMessage;

  CustomMapLayer copyWith({
    String? id,
    String? name,
    String? urlTemplate,
    int? maxZoom,
    MapLayerType? type,
    MapSourceType? sourceType,
    String? filePath,
    double? latitudeOffset,
    double? longitudeOffset,
    bool? enabled,
    double? opacity,
    bool? isRenderable,
    String? validationMessage,
  }) {
    return CustomMapLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      maxZoom: maxZoom ?? this.maxZoom,
      type: type ?? this.type,
      sourceType: sourceType ?? this.sourceType,
      filePath: filePath ?? this.filePath,
      latitudeOffset: latitudeOffset ?? this.latitudeOffset,
      longitudeOffset: longitudeOffset ?? this.longitudeOffset,
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      isRenderable: isRenderable ?? this.isRenderable,
      validationMessage: validationMessage ?? this.validationMessage,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'urlTemplate': urlTemplate,
        'maxZoom': maxZoom,
        'type': type.name,
        'sourceType': sourceType.name,
        'filePath': filePath,
        'latitudeOffset': latitudeOffset,
        'longitudeOffset': longitudeOffset,
        'enabled': enabled,
        'opacity': opacity,
        'isRenderable': isRenderable,
        'validationMessage': validationMessage,
      };

  factory CustomMapLayer.fromJson(Map<String, dynamic> json) {
    return CustomMapLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      urlTemplate: json['urlTemplate'] as String,
      maxZoom: (json['maxZoom'] as num).toInt(),
      type: MapLayerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MapLayerType.base,
      ),
      sourceType: MapSourceType.values.firstWhere(
        (e) => e.name == json['sourceType'],
        orElse: () => MapSourceType.network,
      ),
      filePath: json['filePath'] as String?,
      latitudeOffset: (json['latitudeOffset'] as num?)?.toDouble() ?? 0.0,
      longitudeOffset: (json['longitudeOffset'] as num?)?.toDouble() ?? 0.0,
      enabled: json['enabled'] as bool? ?? true,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 0.55).clamp(0, 1),
      isRenderable: json['isRenderable'] as bool? ?? true,
      validationMessage: json['validationMessage'] as String?,
    );
  }
}

/// Хранилище пользовательских tile-слоёв в SharedPreferences.
class CustomMapRepository {
  static const _storageKey = 'custom_map_layers_v1';
  static const _storageKeyV2 = 'custom_map_layers_v2';

  Future<List<CustomMapLayer>> loadMaps() async {
    final preferences = await SharedPreferences.getInstance();

    // Попытка загрузки из V2
    if (preferences.containsKey(_storageKeyV2)) {
      final rawItems =
          preferences.getStringList(_storageKeyV2) ?? const <String>[];
      return rawItems
          .map((raw) => CustomMapLayer.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ))
          .toList();
    }

    // Миграция из V1
    if (preferences.containsKey(_storageKey)) {
      final rawItems =
          preferences.getStringList(_storageKey) ?? const <String>[];
      final maps = rawItems.map((raw) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return CustomMapLayer.fromJson(json);
      }).toList();

      await _persist(maps);
      await preferences.remove(_storageKey);
      return maps;
    }

    return const <CustomMapLayer>[];
  }

  Future<void> saveMap(CustomMapLayer map) async {
    final maps = await loadMaps();
    final index = maps.indexWhere((item) => item.id == map.id);
    if (index == -1) {
      maps.add(map);
    } else {
      maps[index] = map;
    }
    await _persist(maps);
  }

  Future<void> updateOffset(
      String id, double latitudeOffset, double longitudeOffset) async {
    final maps = await loadMaps();
    final index = maps.indexWhere((item) => item.id == id);
    if (index != -1) {
      maps[index] = maps[index].copyWith(
        latitudeOffset: latitudeOffset,
        longitudeOffset: longitudeOffset,
      );
      await _persist(maps);
    }
  }

  Future<void> updateOpacity(String id, double opacity) async {
    final maps = await loadMaps();
    final index = maps.indexWhere((item) => item.id == id);
    if (index != -1) {
      maps[index] = maps[index].copyWith(opacity: opacity.clamp(0, 1));
      await _persist(maps);
    }
  }

  Future<void> deleteMap(String id) async {
    final maps = await loadMaps();
    maps.removeWhere((item) => item.id == id);
    await _persist(maps);
  }

  Future<void> _persist(List<CustomMapLayer> maps) async {
    final preferences = await SharedPreferences.getInstance();
    final rawItems = maps.map((map) => jsonEncode(map.toJson())).toList();
    await preferences.setStringList(_storageKeyV2, rawItems);
  }
}
