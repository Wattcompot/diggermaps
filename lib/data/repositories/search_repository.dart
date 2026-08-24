import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_config.dart';
import '../../services/network/dio_client.dart';

class SearchResult {
  final String title;
  final String subtitle;
  final LatLng position;
  final String type; // 'osm', 'wikimapia' or 'history'

  const SearchResult({
    required this.title,
    required this.subtitle,
    required this.position,
    required this.type,
  });

  Map<String, Object?> toHistoryJson() => <String, Object?>{
        'title': title,
        'subtitle': subtitle,
        'lat': position.latitude,
        'lng': position.longitude,
        'type': type,
      };

  factory SearchResult.fromHistoryJson(Map<String, dynamic> json) {
    return SearchResult(
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? 'История',
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      type: 'history',
    );
  }
}

class SearchRepository {
  final _dio = DioClient.create();
  static const String _historyKey = 'search_history';

  SearchRepository() {
    _dio.options.headers['User-Agent'] = AppConfig.nominatimUserAgent;
  }

  Future<List<SearchResult>> searchNominatim(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (query.length < 3) return [];

    final response = await _dio.get(
      'https://nominatim.openstreetmap.org/search',
      cancelToken: cancelToken,
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 1,
      },
    );

    if (response.statusCode == 200) {
      final List data = response.data;
      return data.map((item) {
        return SearchResult(
          title: item['display_name'].split(',').first,
          subtitle: item['display_name'],
          position: LatLng(
            double.parse(item['lat']),
            double.parse(item['lon']),
          ),
          type: 'osm',
        );
      }).toList();
    }
    return [];
  }

  Future<List<SearchResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getStringList(_historyKey) ?? const <String>[];

    // Entries written by older builds only contained a text query and have no
    // usable coordinates. They are intentionally skipped instead of moving the
    // map to the incorrect fallback point (0, 0).
    final history = <SearchResult>[];
    for (final raw in rawHistory) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          history.add(SearchResult.fromHistoryJson(decoded));
        }
      } on FormatException {
        // Legacy text-only entry: ignore it safely.
      }
    }
    return history;
  }

  Future<void> addToHistory(SearchResult result) async {
    if (result.title.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    final encoded = jsonEncode(result.toHistoryJson());

    history.removeWhere((raw) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map &&
            decoded['title'] == result.title &&
            decoded['lat'] == result.position.latitude &&
            decoded['lng'] == result.position.longitude;
      } on FormatException {
        return true;
      }
    });
    history.insert(0, encoded);

    if (history.length > 20) {
      history.removeRange(20, history.length);
    }

    await prefs.setStringList(_historyKey, history);
  }
}
