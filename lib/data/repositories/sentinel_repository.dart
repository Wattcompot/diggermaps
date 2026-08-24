import 'dart:async';
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

class SentinelRepository {
  SentinelRepository({Dio? dio}) : _dio = dio ?? DioClient.create();

  final Dio _dio;
  final Map<String, _MosaicData> _mosaicCache = {};
  final Map<String, String> _tileTemplateCache = {};
  final Map<String, _CacheEntry<List<SentinelDateInfo>>> _stacCache = {};
  static const Duration _cacheTtl = Duration(minutes: 30);
  static const Duration _stacCacheTtl = Duration(minutes: 5);

  Future<String> getTileUrl({
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

    final cacheKey = _getCacheKey(from, to, cloudCoverage, preset, bbox);
    String searchId;

    final cached = _mosaicCache[cacheKey] ??
        _findContainingMosaic(from, to, cloudCoverage, preset, bbox);
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheTtl) {
      searchId = cached.searchId;
    } else {
      searchId = await _registerMosaic(from, to, cloudCoverage, bbox);
      _mosaicCache[cacheKey] = _MosaicData(searchId, List<double>.from(bbox),
          from, to, cloudCoverage, preset, DateTime.now());
    }

    final tileKey = '$searchId|$preset';
    return _tileTemplateCache[tileKey] ??= await _getMosaicTileTemplate(
      searchId,
      preset,
    );
  }

  Future<String> _getMosaicTileTemplate(
    String searchId,
    SpectralPreset preset,
  ) async {
    final response = await _dio.get(
      'https://planetarycomputer.microsoft.com/api/data/v1/mosaic/'
      '$searchId/tilejson.json',
      queryParameters: _renderParametersForPreset(preset),
    );
    final tiles = response.data is Map ? response.data['tiles'] : null;
    if (tiles is! List || tiles.isEmpty || tiles.first is! String) {
      throw NoImageryException('Planetary Computer did not return a tile URL');
    }
    return tiles.first as String;
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
        },
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
      _stacCache[cacheKey] = _CacheEntry(result, DateTime.now());
      return result;
    } catch (_) {
      return [];
    }
  }

  String _getCacheKey(DateTime from, DateTime to, double cloud,
      SpectralPreset preset, List<double> bbox) {
    return '${from.toIso8601String()}|${to.toIso8601String()}|$cloud|$preset|${bbox.map((v) => v.toStringAsFixed(3)).join(",")}';
  }

  _MosaicData? _findContainingMosaic(DateTime from, DateTime to, double cloud,
      SpectralPreset preset, List<double> bbox) {
    for (final item in _mosaicCache.values) {
      final width = item.bbox[2] - item.bbox[0];
      final height = item.bbox[3] - item.bbox[1];
      if (item.from == from &&
          item.to == to &&
          item.cloud == cloud &&
          item.preset == preset &&
          bbox[0] >= item.bbox[0] - width * .2 &&
          bbox[1] >= item.bbox[1] - height * .2 &&
          bbox[2] <= item.bbox[2] + width * .2 &&
          bbox[3] <= item.bbox[3] + height * .2) {
        return item;
      }
    }
    return null;
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}

class _MosaicData {
  _MosaicData(this.searchId, this.bbox, this.from, this.to, this.cloud,
      this.preset, this.timestamp);
  final String searchId;
  final List<double> bbox;
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
