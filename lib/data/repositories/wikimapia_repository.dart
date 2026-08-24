import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';
import '../models/wikimapia_models.dart';

class WikimapiaRateLimitException implements Exception {
  final String message;
  WikimapiaRateLimitException(this.message);
  @override
  String toString() => 'WikimapiaRateLimitException: $message';
}

class WikimapiaApiLimitException implements Exception {
  final String message;
  WikimapiaApiLimitException(this.message);
  @override
  String toString() => 'WikimapiaApiLimitException: $message';
}

class WikimapiaRequestCancelledException implements Exception {}

/// Объект Wikimapia для совместимости с существующим UI.
class WikimapiaObject {
  const WikimapiaObject({
    required this.id,
    required this.title,
    required this.description,
    required this.position,
    required this.tags,
  });

  final String id;
  final String title;
  final String description;
  final LatLng position;
  final List<String> tags;
}

class WikimapiaRepository {
  WikimapiaRepository({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;
  CancelToken? _listCancelToken;
  // Ключ 'example' работает для тестов (1 запрос/30 сек).
  // Для нормальной работы зарегистрируй свой на wikimapia.org/api
  final String _apiKey = 'example';
  final String _baseUrl = 'https://api.wikimapia.org/';

  // Rate limiting: 100 requests per 5 minutes
  final List<DateTime> _requestLog = [];
  static const int _maxRequests = 100;
  static const Duration _rateLimitWindow = Duration(minutes: 5);

  // Cache
  final Map<String, _CacheEntry<List<WikimapiaPlace>>> _areaCache = {};
  final Map<String, _CacheEntry<List<WikimapiaPlace>>> _searchCache = {};
  final Map<int, _CacheEntry<WikimapiaPlace>> _placeCache = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Удобный метод для MapScreen.
  /// Если [query] пустой — грузит объекты в видимой области (box).
  /// Если [query] есть — ищет по ключевому слову (search).
  Future<List<WikimapiaPlace>> getPlaces({
    required LatLngBounds bounds,
    String? query,
    int count = 100,
    String language = 'ru',
  }) async {
    if (query != null && query.trim().isNotEmpty) {
      final center = LatLng(
        (bounds.south + bounds.north) / 2,
        (bounds.west + bounds.east) / 2,
      );
      return searchByKeyword(
        query.trim(),
        near: center,
        count: count,
        language: language,
      );
    } else {
      return getPlacesByBox(
        bounds: bounds,
        count: count,
        language: language,
      );
    }
  }

  /// Deprecated 'box' API — единственный стабильный способ получить объекты в bbox
  Future<List<WikimapiaPlace>> getPlacesByBox({
    required LatLngBounds bounds,
    int count = 100,
    int page = 1,
    String language = 'ru',
  }) async {
    final cancelToken = _replaceListCancelToken();
    final cacheKey = '${_bboxKey(bounds)}|box|$page|$language';
    if (_isCacheValid(_areaCache[cacheKey])) {
      return _areaCache[cacheKey]!.data;
    }

    await _checkRateLimit();

    final w = bounds.west.toStringAsFixed(5);
    final s = bounds.south.toStringAsFixed(5);
    final e = bounds.east.toStringAsFixed(5);
    final n = bounds.north.toStringAsFixed(5);

    final Response response;
    try {
      response = await _dio.get(
        _baseUrl,
        cancelToken: cancelToken,
        queryParameters: {
          'key': _apiKey,
          'function': 'box',
          'bbox': '$w,$s,$e,$n',
          'count': count,
          'page': page,
          'format': 'json',
          'data_blocks': 'main,geometry,location,photos,comments',
          'fields': 'description,comments',
          'language': language,
        },
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw WikimapiaRequestCancelledException();
      }
      rethrow;
    }

    _handleStatus(response);

    var places = _extractFolder(response.data)
        .map((e) => WikimapiaPlace.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id > 0 && p.hasValidLocation)
        .toList(growable: false);

    // Some API deployments return an empty folder for box requests. Retry
    // through the public tile endpoint, which is also used by the web map.
    if (places.isEmpty) {
      places = await _getTileFallback(bounds, cancelToken: cancelToken);
    }

    _areaCache[cacheKey] = _CacheEntry(places, DateTime.now());
    return places;
  }

  Future<List<WikimapiaPlace>> getPlacesByArea({
    required LatLngBounds bounds,
    int count = 100,
    String language = 'ru',
  }) =>
      getPlacesByBox(bounds: bounds, count: count, language: language);

  static List<WikimapiaPlace> filterPlaces(
    List<WikimapiaPlace> places,
    List<String> tags,
  ) {
    if (tags.isEmpty) return places;
    final normalized = tags.map((tag) => tag.toLowerCase()).toList();
    return places.where((place) {
      final searchable = <String>[
        place.title,
        place.description,
        ...place.categories.map((category) => category.title),
      ].join(' ').toLowerCase();
      return normalized.every(searchable.contains);
    }).toList(growable: false);
  }

  /// Deprecated 'search' API — текстовый поиск по всей базе Wikimapia.
  /// Возвращает до [count] результатов, отсортированных по близости к [near].
  Future<List<WikimapiaPlace>> searchByKeyword(
    String query, {
    LatLng? near,
    int count = 100,
    int page = 1,
    String language = 'ru',
  }) async {
    final cancelToken = _replaceListCancelToken();
    final normalized = query.trim().toLowerCase();
    final cacheKey = 'search|$normalized|'
        '${near?.latitude.toStringAsFixed(4) ?? ''}|'
        '${near?.longitude.toStringAsFixed(4) ?? ''}|$page|$language';

    if (_isCacheValid(_searchCache[cacheKey])) {
      return _searchCache[cacheKey]!.data;
    }

    await _checkRateLimit();

    final params = <String, dynamic>{
      'key': _apiKey,
      'function': 'search',
      'q': query,
      'count': count,
      'page': page,
      'format': 'json',
      'language': language,
    };

    if (near != null) {
      params['lat'] = near.latitude;
      params['lon'] = near.longitude;
    }

    final Response response;
    try {
      response = await _dio.get(
        _baseUrl,
        queryParameters: params,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw WikimapiaRequestCancelledException();
      }
      rethrow;
    }
    _handleStatus(response);

    final places = _extractFolder(response.data)
        .map((e) => WikimapiaPlace.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id > 0 && p.hasValidLocation)
        .toList(growable: false);

    _searchCache[cacheKey] = _CacheEntry(places, DateTime.now());
    return places;
  }

  /// Алиас для обратной совместимости (используется в поиске топбара).
  Future<List<WikimapiaPlace>> searchPlaces(
    String query, {
    LatLng? near,
    int count = 50,
    String language = 'ru',
  }) =>
      searchByKeyword(query, near: near, count: count, language: language);

  /// Полная информация об объекте (описание, фото, комментарии).
  /// Использует рабочий 'place.getbyid'.
  Future<WikimapiaPlace> getPlaceById(int id, {String language = 'ru'}) async {
    if (_isCacheValid(_placeCache[id])) {
      return _placeCache[id]!.data;
    }

    await _checkRateLimit();

    final response = await _dio.get(
      _baseUrl,
      queryParameters: {
        'key': _apiKey,
        'function': 'place.getbyid',
        'id': id,
        'format': 'json',
        'language': language,
        'data_blocks': 'main,geometry,location,photos,comments',
      },
    );

    _handleStatus(response);

    final place =
        WikimapiaPlace.fromJson(response.data as Map<String, dynamic>);
    _placeCache[id] = _CacheEntry(place, DateTime.now());
    return place;
  }

  // --- Helpers ---

  CancelToken _replaceListCancelToken() {
    _listCancelToken?.cancel('Superseded by a newer Wikimapia request');
    return _listCancelToken = CancelToken();
  }

  Future<List<WikimapiaPlace>> _getTileFallback(
    LatLngBounds bounds, {
    required CancelToken cancelToken,
  }) async {
    const zoom = 8;
    final center = LatLng(
      (bounds.south + bounds.north) / 2,
      (bounds.west + bounds.east) / 2,
    );
    final x = ((center.longitude + 180) / 360 * (1 << zoom)).floor();
    final y = ((1 -
                math.log(math.tan(center.latitude * math.pi / 180) +
                        1 / math.cos(center.latitude * math.pi / 180)) /
                    math.pi) /
            2 *
            (1 << zoom))
        .floor();
    final response = await _dio.get(
      _baseUrl,
      cancelToken: cancelToken,
      queryParameters: {
        'key': _apiKey,
        'function': 'tile',
        'z': zoom,
        'x': x,
        'y': y,
        'language': 'ru',
        'format': 'json',
      },
    );
    _handleStatus(response);
    final List<dynamic> data =
        response.data is List ? response.data : _extractFolder(response.data);
    return data
        .whereType<Map>()
        .map((e) => WikimapiaPlace.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id > 0 && p.hasValidLocation)
        .toList(growable: false);
  }

  List<dynamic> _extractFolder(dynamic data) {
    if (data is! Map) return const [];
    final folder = data['folder'];
    return folder is List ? folder : const [];
  }

  void _handleStatus(Response response) {
    if (response.statusCode == 429) {
      throw WikimapiaRateLimitException('Rate limit exceeded (429)');
    }
    if (response.data is! Map) return;

    final data = response.data as Map;
    final error = data['error'];
    final debug = data['debug'];
    final code = error is Map
        ? error['code']
        : debug is Map
            ? debug['code']
            : null;
    final message = error is Map
        ? error['message']
        : debug is Map
            ? debug['message']
            : null;

    if (code == 429 || code?.toString() == '429') {
      throw WikimapiaRateLimitException('Rate limit exceeded');
    }
    if (code == 1004 || code?.toString() == '1004') {
      throw WikimapiaApiLimitException(
          'API limit exhausted. Use your own key.');
    }
    if (code != null && code.toString() != '0') {
      throw StateError('Wikimapia API $code: ${message ?? "unknown"}');
    }
  }

  Future<void> _checkRateLimit() async {
    final now = DateTime.now();
    _requestLog.removeWhere((dt) => now.difference(dt) > _rateLimitWindow);
    if (_requestLog.length >= _maxRequests) {
      throw WikimapiaRateLimitException('Local rate limit (100/5min)');
    }
    _requestLog.add(now);
  }

  String _bboxKey(LatLngBounds b) {
    return '${b.west.toStringAsFixed(4)},${b.south.toStringAsFixed(4)},'
        '${b.east.toStringAsFixed(4)},${b.north.toStringAsFixed(4)}';
  }

  bool _isCacheValid(_CacheEntry? entry) {
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) < _cacheTtl;
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}
