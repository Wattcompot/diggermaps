import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../services/network/dio_client.dart';

enum SpectralPreset {
  naturalColor,
}

class NoImageryException implements Exception {
  final String message;
  NoImageryException(this.message);
  @override
  String toString() => 'NoImageryException: $message';
}

/// Источник тайлов мозаики: URL-шаблон и лимиты зума самого источника
/// (из TileJSON), а не «угаданные» значения.
///
/// `maxZoom == null`, если источник не сообщил его в TileJSON.
class SentinelTileSource {
  const SentinelTileSource({
    required this.urlTemplate,
    this.minZoom = 0,
    this.maxZoom,
    this.tileDimension = 256,
  });

  final String urlTemplate;
  final int minZoom;
  final int? maxZoom;
  final int tileDimension;

  @override
  String toString() => 'SentinelTileSource(min=$minZoom, max=$maxZoom, '
      'tile=$tileDimension, $urlTemplate)';
}

class SentinelRepository {
  SentinelRepository({Dio? dio}) : _dio = dio ?? DioClient.create();

  final Dio _dio;
  final Map<String, _MosaicData> _mosaicCache = {};
  final Map<String, SentinelTileSource> _tileSourceCache = {};
  final Map<String, _CacheEntry<List<SentinelDateInfo>>> _stacCache = {};

  static const Duration _cacheTtl = Duration(minutes: 30);
  static const Duration _stacCacheTtl = Duration(minutes: 5);

  /// Жёсткие границы кэшей: без них кэш мозаик рос бесконечно.
  static const int _maxMosaicCacheEntries = 24;
  static const int _maxTileSourceCacheEntries = 48;
  static const int _maxStacCacheEntries = 12;

  /// Шаг «устойчивой» сетки, по которой выравнивается bbox запроса.
  ///
  /// Это основной механизм стабильности URL: одинаковые (или слегка
  /// сдвинутые) окна дают один и тот же выровненный bbox => один и тот же
  /// `searchId` => один и тот же URL, поэтому слой не пересобирается.
  /// Дополнительно работает переиспользование по покрытию: любое окно внутри
  /// уже зарегистрированной мозаики тоже получает тот же URL.
  static const double _bboxQuantumDegrees = 0.05;

  static const double _minLatitude = -85.0511287798;
  static const double _maxLatitude = 85.0511287798;

  Future<String> getTileUrl({
    required DateTime date,
    required double cloudCoverage,
    required SpectralPreset preset,
    DateTime? dateFrom,
    DateTime? dateTo,
    required List<double> bbox,
  }) async {
    final source = await getTileSource(
      date: date,
      cloudCoverage: cloudCoverage,
      preset: preset,
      dateFrom: dateFrom,
      dateTo: dateTo,
      bbox: bbox,
    );
    return source.urlTemplate;
  }

  /// Возвращает источник тайлов для запрошенной области.
  ///
  /// Мозаика переиспользуется, если запрошенный bbox **полностью** покрыт
  /// ранее зарегистрированной областью (с учётом запаса) и параметры
  /// (период/облачность/пресет) совпадают.
  Future<SentinelTileSource> getTileSource({
    required DateTime date,
    required double cloudCoverage,
    required SpectralPreset preset,
    DateTime? dateFrom,
    DateTime? dateTo,
    required List<double> bbox,
  }) async {
    final now = DateTime.now().toUtc();
    final selectedDate = date.toUtc();
    final from =
        (dateFrom ?? selectedDate.subtract(const Duration(days: 30))).toUtc();
    final requestedTo = (dateTo ?? selectedDate).toUtc();
    final to = requestedTo.isAfter(now) ? now : requestedTo;

    final snapped = _snapBbox(bbox);
    var mosaic =
        _findContainingMosaic(from, to, cloudCoverage, preset, snapped);
    if (mosaic == null) {
      final searchId = await _registerMosaic(from, to, cloudCoverage, snapped);
      mosaic = _MosaicData(
        searchId,
        snapped,
        from,
        to,
        cloudCoverage,
        preset,
        DateTime.now(),
      );
      _storeMosaic(mosaic);
    }

    final tileKey = '${mosaic.searchId}|$preset';
    final cached = _tileSourceCache[tileKey];
    if (cached != null) return cached;

    final source = await _getMosaicTileSource(mosaic.searchId, preset);
    _putBounded(_tileSourceCache, tileKey, source, _maxTileSourceCacheEntries);
    return source;
  }

  Future<SentinelTileSource> _getMosaicTileSource(
    String searchId,
    SpectralPreset preset,
  ) async {
    final response = await _dio.get(
      'https://planetarycomputer.microsoft.com/api/data/v1/mosaic/'
      '$searchId/tilejson.json',
      queryParameters: _renderParametersForPreset(preset),
    );
    final data = response.data;
    final tiles = data is Map ? data['tiles'] : null;
    if (tiles is! List || tiles.isEmpty || tiles.first is! String) {
      throw NoImageryException('Planetary Computer did not return a tile URL');
    }
    return SentinelTileSource(
      urlTemplate: tiles.first as String,
      minZoom: _readInt(data, const ['minzoom']) ?? 0,
      maxZoom: _readInt(data, const ['maxzoom']),
      tileDimension:
          _readInt(data, const ['tile_size', 'tilesize', 'tileDimension']) ??
              256,
    );
  }

  int? _readInt(Object? data, List<String> keys) {
    if (data is! Map) return null;
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<String> _registerMosaic(
      DateTime from, DateTime to, double cloud, List<double> bbox) async {
    try {
      final searchParams = {
        "collections": ["sentinel-2-l2a"],
        "datetime":
            "${DateFormat('yyyy-MM-ddT00:00:00Z').format(from)}/${DateFormat('yyyy-MM-ddT23:59:59Z').format(to)}",
        "query": {
          "eo:cloud_cover": {"lt": cloud}
        },
        "bbox": bbox,
        "sortby": [
          {"field": "properties.datetime", "direction": "desc"}
        ],
      };

      final response = await _dio.post(
        'https://planetarycomputer.microsoft.com/api/data/v1/mosaic/register',
        data: searchParams,
      );

      final searchId = response.data['searchid'];
      if (searchId == null) {
        throw NoImageryException(
            'Failed to register mosaic: No search ID returned');
      }
      return searchId;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw NoImageryException('No imagery found for the given parameters');
      }
      rethrow;
    }
  }

  Map<String, dynamic> _renderParametersForPreset(SpectralPreset preset) {
    final parameters = <String, dynamic>{
      'collection': 'sentinel-2-l2a',
      'nodata': 0,
      'format': 'png',
    };
    switch (preset) {
      case SpectralPreset.naturalColor:
        return <String, dynamic>{
          ...parameters,
          'assets': 'visual',
          'asset_bidx': 'visual|1,2,3',
        };
    }
  }

  /// Запрашивает доступные даты с облачностью через STAC API.
  Future<List<SentinelDateInfo>> queryDates({
    required List<double> bbox,
    DateTime? from,
    DateTime? to,
  }) async {
    final fromDate = from ?? DateTime.now().subtract(const Duration(days: 365));
    final toDate = to ?? DateTime.now();
    final fromStr = DateFormat('yyyy-MM-ddTHH:mm:ss').format(fromDate);
    final toStr = DateFormat('yyyy-MM-ddTHH:mm:ss').format(toDate);
    final cacheKey =
        '${bbox.map((v) => v.toStringAsFixed(3)).join(',')}|$fromStr|$toStr';
    final cached = _stacCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _stacCacheTtl) {
      return cached.data;
    }

    try {
      var url = 'https://planetarycomputer.microsoft.com/api/stac/v1/search';
      Map<String, dynamic> requestData = {
        "collections": ["sentinel-2-l2a"],
        "bbox": bbox,
        "datetime": "${fromStr}Z/${toStr}Z",
        "limit": 100,
        "sortby": [
          {"field": "properties.datetime", "direction": "desc"}
        ],
        "fields": {
          "include": [
            "properties.datetime",
            "properties.eo:cloud_cover",
          ]
        }
      };
      final features = <dynamic>[];
      final visited = <String>{};
      while (visited.add(url)) {
        final response = await _dio.post(url, data: requestData);
        final data = response.data as Map<String, dynamic>? ?? const {};
        features.addAll(data['features'] as List? ?? const []);
        final links = data['links'] as List? ?? const [];
        Map? next;
        for (final link in links.whereType<Map>()) {
          if (link['rel'] == 'next') {
            next = link;
            break;
          }
        }
        if (next == null || next['href'] == null) break;
        url = next['href'].toString();
        final body = next['body'];
        if (body is Map) requestData = Map<String, dynamic>.from(body);
      }
      final result = features
          .map((f) {
            final props = f['properties'] as Map<String, dynamic>? ?? {};
            final dt = DateTime.tryParse(props['datetime']?.toString() ?? '');
            final cloud = (props['eo:cloud_cover'] as num?)?.toDouble() ?? 100;
            return SentinelDateInfo(date: dt, cloudCover: cloud);
          })
          .where((d) => d.date != null)
          .toList();
      _putBounded(_stacCache, cacheKey, _CacheEntry(result, DateTime.now()),
          _maxStacCacheEntries);
      return result;
    } catch (_) {
      return [];
    }
  }

  String _getCacheKey(DateTime from, DateTime to, double cloud,
      SpectralPreset preset, List<double> bbox) {
    return '${from.toIso8601String()}|${to.toIso8601String()}|$cloud|$preset|${bbox.map((v) => v.toStringAsFixed(4)).join(",")}';
  }

  /// Выравнивает bbox наружу по устойчивой сетке [_bboxQuantumDegrees].
  ///
  /// Именно это (а не произвольный «запас») даёт устойчивость URL: слегка
  /// сдвинутые окна дают один и тот же выровненный bbox, а покрытие мозаики
  /// совпадает с областью, реально запрошенной у сервера, поэтому проверка
  /// вхождения не «прощает» выход за покрытие.
  List<double> _snapBbox(List<double> bbox) {
    final west = math.min(bbox[0], bbox[2]);
    final east = math.max(bbox[0], bbox[2]);
    final south = math.min(bbox[1], bbox[3]);
    final north = math.max(bbox[1], bbox[3]);
    return <double>[
      _floorToQuantum(west).clamp(-180.0, 180.0),
      _floorToQuantum(south).clamp(_minLatitude, _maxLatitude),
      _ceilToQuantum(east).clamp(-180.0, 180.0),
      _ceilToQuantum(north).clamp(_minLatitude, _maxLatitude),
    ];
  }

  static double _floorToQuantum(double value) =>
      (value / _bboxQuantumDegrees).floorToDouble() * _bboxQuantumDegrees;

  static double _ceilToQuantum(double value) =>
      (value / _bboxQuantumDegrees).ceilToDouble() * _bboxQuantumDegrees;

  void _storeMosaic(_MosaicData mosaic) {
    final key = _getCacheKey(
      mosaic.from,
      mosaic.to,
      mosaic.cloud,
      mosaic.preset,
      mosaic.coverage,
    );
    _putBounded(_mosaicCache, key, mosaic, _maxMosaicCacheEntries);
  }

  static void _putBounded<K, V>(
    Map<K, V> cache,
    K key,
    V value,
    int maxEntries,
  ) {
    cache.remove(key);
    cache[key] = value;
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
  }

  _MosaicData? _findContainingMosaic(DateTime from, DateTime to, double cloud,
      SpectralPreset preset, List<double> bbox) {
    _MosaicData? best;
    for (final item in _mosaicCache.values) {
      if (item.from != from ||
          item.to != to ||
          item.cloud != cloud ||
          item.preset != preset) {
        continue;
      }
      if (DateTime.now().difference(item.timestamp) >= _cacheTtl) continue;
      // Строгое покрытие: раньше допускалось 20% «наружу», из-за чего запрос
      // вне покрытия подписывался на мозаику без данных (пустые тайлы).
      if (!_contains(item.coverage, bbox)) continue;
      if (best == null || _area(item.coverage) < _area(best.coverage)) {
        best = item;
      }
    }
    return best;
  }

  static bool _contains(List<double> outer, List<double> inner) {
    final innerWest = inner[0] < inner[2] ? inner[0] : inner[2];
    final innerEast = inner[0] < inner[2] ? inner[2] : inner[0];
    final innerSouth = inner[1] < inner[3] ? inner[1] : inner[3];
    final innerNorth = inner[1] < inner[3] ? inner[3] : inner[1];
    return innerWest >= outer[0] &&
        innerEast <= outer[2] &&
        innerSouth >= outer[1] &&
        innerNorth <= outer[3];
  }

  static double _area(List<double> bbox) {
    final width = (bbox[2] - bbox[0]).abs();
    final height = (bbox[3] - bbox[1]).abs();
    return width * height;
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}

class _MosaicData {
  _MosaicData(this.searchId, this.coverage, this.from, this.to, this.cloud,
      this.preset, this.timestamp);
  final String searchId;

  /// Область, на которую зарегистрирована мозаика: выровненный bbox, он же
  /// ушёл в запрос регистрации.
  final List<double> coverage;
  final DateTime from;
  final DateTime to;
  final double cloud;
  final SpectralPreset preset;
  final DateTime timestamp;
}

class SentinelDateInfo {
  final DateTime? date;
  final double cloudCover;
  const SentinelDateInfo({this.date, this.cloudCover = 100});
}
