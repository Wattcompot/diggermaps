import 'package:latlong2/latlong.dart';

class WikimapiaCategory {
  final int id;
  final String title;

  WikimapiaCategory({required this.id, required this.title});

  factory WikimapiaCategory.fromJson(Map<String, dynamic> json) {
    return WikimapiaCategory(
      id: _toInt(json['id']),
      title: json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown',
    );
  }
}

class WikimapiaPhoto {
  final String thumbnail;
  final String full;

  WikimapiaPhoto({required this.thumbnail, required this.full});

  factory WikimapiaPhoto.fromJson(Map<String, dynamic> json) {
    return WikimapiaPhoto(
      thumbnail: (json['thumbnail'] ??
              json['thumbnail_url'] ??
              json['thumb'] ??
              json['url'] ??
              '')
          .toString(),
      full: (json['big'] ?? json['full'] ?? json['url'] ?? '').toString(),
    );
  }
}

class WikimapiaComment {
  final String text;
  final String author;
  final DateTime date;

  WikimapiaComment({
    required this.text,
    required this.author,
    required this.date,
  });

  factory WikimapiaComment.fromJson(Map<String, dynamic> json) {
    return WikimapiaComment(
      text: (json['text'] ??
              json['message'] ??
              json['comment'] ??
              json['body'] ??
              '')
          .toString(),
      author: (json['user_name'] ?? json['author'] ?? '').toString(),
      date: json['date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(_toInt(json['date']) * 1000)
          : DateTime.now(),
    );
  }
}

class WikimapiaPlace {
  final int id;
  final String title;
  final String description;
  final List<WikimapiaCategory> categories;
  final List<LatLng> polygon;
  final LatLng location;
  final String url;
  final List<WikimapiaPhoto> photos;
  final List<WikimapiaComment> comments;
  final bool detailsLoaded;

  WikimapiaPlace({
    required this.id,
    required this.title,
    required this.description,
    required this.categories,
    required this.polygon,
    required this.location,
    required this.url,
    this.photos = const [],
    this.comments = const [],
    this.detailsLoaded = false,
  });

  bool get hasValidLocation =>
      location.latitude.abs() <= 90 &&
      location.longitude.abs() <= 180 &&
      (location.latitude != 0 || location.longitude != 0);

  factory WikimapiaPlace.fromJson(Map<String, dynamic> json) {
    final locationData = _placeField(json, 'location');
    final location = locationData is Map
        ? Map<String, dynamic>.from(locationData)
        : const <String, dynamic>{};
    final lat = _toDouble(location['lat'] ?? json['lat']);
    final lon = _toDouble(location['lon'] ?? json['lon']);

    final polyPoints = <LatLng>[];
    final polygon =
        _placeField(json, 'polygon') ?? _placeField(json, 'geometry');
    if (polygon is List) {
      for (final point in polygon) {
        if (point is! Map) continue;
        final latitude = _toDouble(point['y'] ?? point['lat']);
        final longitude = _toDouble(point['x'] ?? point['lon']);
        if (latitude.abs() <= 90 && longitude.abs() <= 180) {
          polyPoints.add(LatLng(latitude, longitude));
        }
      }
    }

    final id = _toInt(_placeField(json, 'id'));
    final locationIsValid =
        lat.abs() <= 90 && lon.abs() <= 180 && (lat != 0 || lon != 0);
    final resolvedLocation = locationIsValid
        ? LatLng(lat, lon)
        : polyPoints.length >= 3
            ? LatLng(
                polyPoints.fold<double>(0, (sum, p) => sum + p.latitude) /
                    polyPoints.length,
                polyPoints.fold<double>(0, (sum, p) => sum + p.longitude) /
                    polyPoints.length,
              )
            : const LatLng(0, 0);

    final rawTags =
        _placeField(json, 'tags') ?? _placeField(json, 'categories');
    final categories = _parseList(rawTags, WikimapiaCategory.fromJson);
    final name = _placeField(json, 'name')?.toString().trim() ?? '';
    final title = _placeField(json, 'title')?.toString().trim() ?? '';
    final stringTags = rawTags is List
        ? rawTags
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final firstTag = [
      ...categories.map((category) => category.title),
      ...stringTags
    ]
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final rawTitle = name.isNotEmpty
        ? name
        : title.isNotEmpty
            ? title
            : firstTag.isNotEmpty
                ? firstTag
                : 'Без названия';
    final tagDescription = [
      ...categories.map((category) => category.title.trim()),
      ...stringTags,
    ].where((value) => value.isNotEmpty).join(', ');
    final rawDescription = _placeField(json, 'description') ??
        _placeField(json, 'wiki') ??
        _placeField(json, 'wikipedia');
    final rawComments = _placeField(json, 'comments');
    final description = [
      rawDescription,
      tagDescription,
    ].map((value) => value?.toString().trim() ?? '').firstWhere(
        (value) => value.isNotEmpty,
        orElse: () => 'Описание отсутствует');

    return WikimapiaPlace(
      id: id,
      title: rawTitle,
      description: description,
      url: _parsePlaceUrl(json['url'], json['urlhtml'], id),
      location: resolvedLocation,
      polygon: polyPoints,
      categories: categories,
      photos: _parseList(_placeField(json, 'photos'), WikimapiaPhoto.fromJson),
      comments: _parseList(rawComments, WikimapiaComment.fromJson),
      detailsLoaded: rawDescription != null || rawComments != null,
    );
  }
}

dynamic _placeField(Map<String, dynamic> json, String key) {
  final direct = json[key];
  if (direct != null) return direct;
  for (final container in const [
    'main',
    'place',
    'object',
    'data',
    'info',
    'geometry'
  ]) {
    final nested = json[container];
    if (nested is Map) {
      final value = _placeField(Map<String, dynamic>.from(nested), key);
      if (value != null) return value;
    }
  }
  return null;
}

String _parsePlaceUrl(dynamic directUrl, dynamic htmlUrl, int id) {
  final direct = directUrl?.toString().trim() ?? '';
  if (direct.startsWith('http://') || direct.startsWith('https://')) {
    return direct.replaceFirst('http://', 'https://');
  }

  final html = htmlUrl?.toString() ?? '';
  final match = RegExp(r"""href=["']([^"']+)["']""", caseSensitive: false)
      .firstMatch(html);
  final href = match?.group(1)?.replaceAll(r'\/', '/') ?? '';
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href.replaceAll('&amp;', '&').replaceFirst('http://', 'https://');
  }

  return id > 0 ? 'https://wikimapia.org/$id' : '';
}

List<T> _parseList<T>(
  dynamic value,
  T Function(Map<String, dynamic>) parser,
) {
  final items = value is Map
      ? value['items'] ?? value['folder'] ?? value['data'] ?? const []
      : value;
  if (items is! List) return const [];
  return items
      .whereType<Map>()
      .map((item) => parser(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}
