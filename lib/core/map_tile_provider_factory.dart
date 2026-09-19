import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';

import '../data/models/imported_map.dart';
import '../data/repositories/custom_map_repository.dart';
import '../services/tile_cache/network_tile_provider_factory.dart';
import '../services/tile_cache/retained_tile_provider.dart';
import 'constants/map_layers.dart';
import 'map_formats/jnx_decoder.dart';
import 'map_formats/jnx_tile_provider.dart';
import 'map_formats/local_raster_tile_provider.dart';
import 'map_formats/map_calibration.dart';
import 'map_formats/ozf2_decoder.dart';
import 'map_formats/ozf2_tile_provider.dart';
import 'map_formats/ozf_tile_provider.dart';

class MapTileProviderFactory {
  MapTileProviderFactory({
    required this.camera,
    this.onProviderReady,
  });

  final MapCamera Function() camera;
  final VoidCallback? onProviderReady;

  final Map<String, MbTiles> _mbtilesCache = <String, MbTiles>{};
  final Map<String, OzfTileProvider> _importedOzfProviders =
      <String, OzfTileProvider>{};
  final Map<String, LocalRasterTileProvider> _importedRasterProviders =
      <String, LocalRasterTileProvider>{};
  final Map<String, OzfDecoder> _ozfCache = <String, OzfDecoder>{};
  final Map<String, OziMapCalibration> _calibrationCache =
      <String, OziMapCalibration>{};
  final Map<String, JnxDecoder> _jnxCache = <String, JnxDecoder>{};
  final Map<String, RetainedTileProvider> _baseProviders =
      <String, RetainedTileProvider>{};
  bool _disposed = false;

  /// Провайдер базового тайлового слоя.
  ///
  /// Создаётся и кэшируется здесь, а не в `build()` слоя: [TileLayer] вызывает
  /// `tileProvider.dispose()` при удалении своего состояния (смена ключа слоя,
  /// выключение слоя) — а провайдер с прогретым кэшем FMTC должен это
  /// переживать. Поэтому наружу отдаётся [RetainedTileProvider], а сам FMTC
  /// провайдер живёт до [dispose] фабрики.
  TileProvider baseTileProvider(String storeName) {
    if (kIsWeb) {
      return _baseProviders.putIfAbsent(
        'network',
        () => RetainedTileProvider(createNetworkTileProvider()),
      );
    }
    return _baseProviders.putIfAbsent(
      storeName,
      () => RetainedTileProvider(
        FMTCTileProvider(
          stores: <String, BrowseStoreStrategy>{
            storeName: BrowseStoreStrategy.readUpdateCreate,
          },
          loadingStrategy: BrowseLoadingStrategy.cacheFirst,
          recordHitsAndMisses: false,
        ),
      ),
    );
  }

  MbTiles mbtiles(String path) {
    if (kIsWeb) throw UnsupportedError('MBTiles not supported on Web');
    return _mbtilesCache.putIfAbsent(path, () => MbTiles(mbtilesPath: path));
  }

  Widget? buildImportedLayer(ImportedMap map, double baseMaxZoom) {
    final path = map.imageFilePath;
    if (path == null || !File(path).existsSync()) return null;

    if (map.isMbtiles) {
      final source = mbtiles(path);
      final metadata = source.getMetadata();
      return Opacity(
        key: ValueKey('imported-map-${map.id}'),
        opacity: map.opacity.clamp(0, 1),
        child: TileLayer(
          tileProvider: MbTilesTileProvider(mbtiles: source),
          minNativeZoom: metadata.minZoom?.round() ?? 0,
          maxNativeZoom: metadata.maxZoom?.round() ?? 19,
          maxZoom: baseMaxZoom,
          panBuffer: 0,
          keepBuffer: 1,
          tileDisplay: const TileDisplay.instantaneous(),
          tileBounds: importedMapBounds(map),
          tileBuilder: (context, tileWidget, tile) => Transform.translate(
            offset: importedMapScreenOffset(map),
            child: tileWidget,
          ),
        ),
      );
    }

    final bounds = map.parsedBounds;
    if (bounds == null) return null;
    try {
      final format = map.format.toLowerCase();
      if (format == 'ozf2' || format == 'ozfx3' || format == 'ozf') {
        final key = '${map.id}:$path:${map.offsetX}:${map.offsetY}';
        final provider = _importedOzfProviders.putIfAbsent(
          key,
          () => OzfTileProvider(
            ozfPath: path,
            minLatitude: bounds['minLat']! + map.offsetY,
            maxLatitude: bounds['maxLat']! + map.offsetY,
            minLongitude: bounds['minLng']! + map.offsetX,
            maxLongitude: bounds['maxLng']! + map.offsetX,
          ),
        );
        return Opacity(
          key: ValueKey('imported-map-${map.id}'),
          opacity: map.opacity.clamp(0, 1),
          child: TileLayer(
            tileProvider: provider,
            maxZoom: baseMaxZoom,
            panBuffer: 0,
            keepBuffer: 1,
            tileDisplay: const TileDisplay.instantaneous(),
            tileBounds: importedMapBounds(map),
          ),
        );
      }

      final key = '${map.id}:$path:${map.offsetX}:${map.offsetY}';
      final provider = _importedRasterProviders.putIfAbsent(
        key,
        () => LocalRasterTileProvider(
          imagePath: path,
          minLatitude: bounds['minLat']! + map.offsetY,
          maxLatitude: bounds['maxLat']! + map.offsetY,
          minLongitude: bounds['minLng']! + map.offsetX,
          maxLongitude: bounds['maxLng']! + map.offsetX,
        ),
      );
      return Opacity(
        key: ValueKey('imported-map-${map.id}'),
        opacity: map.opacity.clamp(0, 1),
        child: TileLayer(
          tileProvider: provider,
          maxZoom: baseMaxZoom,
          panBuffer: 0,
          keepBuffer: 1,
          tileDisplay: const TileDisplay.instantaneous(),
          tileBounds: importedMapBounds(map),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Ozf2TileProvider? buildOzf2Provider(CustomMapLayer map) {
    try {
      late final String ozfPath;
      late final String? mapPath;
      if (map.sourceType == MapSourceType.ozf2) {
        ozfPath = map.urlTemplate;
        mapPath = findCalibrationFile(ozfPath);
      } else {
        mapPath = map.urlTemplate;
        ozfPath = findOzf2ForMap(mapPath);
      }
      if (ozfPath.isEmpty || mapPath == null || mapPath.isEmpty) return null;
      final decoder = _ozfCache.putIfAbsent(
        ozfPath,
        () => OzfDecoder.open(ozfPath),
      );
      final calibration = _calibrationCache.putIfAbsent(
        mapPath,
        () => OziMapCalibration.fromFile(mapPath!),
      );
      return Ozf2TileProvider(decoder: decoder, calibration: calibration);
    } catch (_) {
      return null;
    }
  }

  JnxTileProvider buildJnxProvider(CustomMapLayer map) {
    if (!_jnxCache.containsKey(map.urlTemplate)) {
      initJnxDecoder(map.urlTemplate);
    }
    return JnxTileProvider(
      decoder: _jnxCache[map.urlTemplate] ?? JnxDecoder.empty(map.urlTemplate),
    );
  }

  void initJnxDecoder(String path) {
    JnxDecoder.open(path).then((decoder) {
      if (_disposed) {
        decoder.dispose();
        return;
      }
      _jnxCache[path] = decoder;
      onProviderReady?.call();
    });
  }

  String? findCalibrationFile(String ozfPath) {
    final lower = ozfPath.toLowerCase();
    if (lower.endsWith('.ozf2') || lower.endsWith('.ozfx3')) {
      final dot = ozfPath.lastIndexOf('.');
      final candidate = '${ozfPath.substring(0, dot)}.map';
      if (File(candidate).existsSync()) return candidate;
    }
    final directory = Directory(ozfPath).parent;
    if (!directory.existsSync()) return null;
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.map'))
        .toList(growable: false);
    return files.isEmpty ? null : files.last.path;
  }

  String findOzf2ForMap(String mapPath) {
    final base =
        mapPath.replaceAll(RegExp(r'\.map$', caseSensitive: false), '');
    for (final extension in <String>['.ozf2', '.OZF2', '.ozfx3', '.OZFX3']) {
      final candidate = '$base$extension';
      if (File(candidate).existsSync()) return candidate;
    }
    final directory = Directory(mapPath).parent;
    if (!directory.existsSync()) return '';
    final files = directory.listSync().whereType<File>().where((file) {
      final path = file.path.toLowerCase();
      return path.endsWith('.ozf2') || path.endsWith('.ozfx3');
    }).toList(growable: false);
    return files.isEmpty ? '' : files.last.path;
  }

  LatLngBounds importedMapBounds(ImportedMap map) {
    final bounds = map.parsedBounds!;
    return LatLngBounds(
      LatLng(bounds['minLat']! + map.offsetY, bounds['minLng']! + map.offsetX),
      LatLng(bounds['maxLat']! + map.offsetY, bounds['maxLng']! + map.offsetX),
    );
  }

  Offset importedMapScreenOffset(ImportedMap map) => _screenOffset(
        latitudeOffset: map.offsetY,
        longitudeOffset: map.offsetX,
      );

  Offset customLayerScreenOffset(CustomMapLayer map) => _screenOffset(
        latitudeOffset: map.latitudeOffset,
        longitudeOffset: map.longitudeOffset,
      );

  Offset _screenOffset({
    required double latitudeOffset,
    required double longitudeOffset,
  }) {
    if (latitudeOffset == 0 && longitudeOffset == 0) return Offset.zero;
    final mapCamera = camera();
    final worldSize = 256.0 * math.pow(2, mapCamera.zoom);
    final longitudePixels = longitudeOffset / 360 * worldSize;

    double mercatorY(double latitude) {
      final radians = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
      return (1 -
              math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
          2 *
          worldSize;
    }

    final latitudePixels =
        mercatorY(mapCamera.center.latitude + latitudeOffset) -
            mercatorY(mapCamera.center.latitude);
    return Offset(longitudePixels, latitudePixels);
  }

  Widget buildNetworkCustomLayer(CustomMapLayer map) => Opacity(
        opacity: map.opacity,
        child: TileLayer(
          urlTemplate: map.urlTemplate,
          tileProvider: createNetworkTileProvider(),
          maxZoom: map.maxZoom.toDouble(),
          panBuffer: 2,
          keepBuffer: 4,
          subdomains: MapLayers.tileSubdomains,
          userAgentPackageName: MapLayers.userAgentPackageName,
          tileBuilder: (context, tileWidget, tile) => Transform.translate(
            offset: customLayerScreenOffset(map),
            child: tileWidget,
          ),
        ),
      );

  void dispose() {
    _disposed = true;
    for (final provider in _baseProviders.values) {
      // FMTC освобождает ресурсы асинхронно; ждать здесь нельзя, но и терять
      // провайдера с прогретым кэшем при переключении слоя — нельзя тоже.
      provider.inner.dispose();
    }
    _baseProviders.clear();
    for (final value in _mbtilesCache.values) {
      value.dispose();
    }
    for (final value in _ozfCache.values) {
      value.dispose();
    }
    for (final value in _jnxCache.values) {
      value.dispose();
    }
    _mbtilesCache.clear();
    _importedOzfProviders.clear();
    _importedRasterProviders.clear();
    _ozfCache.clear();
    _calibrationCache.clear();
    _jnxCache.clear();
  }
}
