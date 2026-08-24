import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/wikimapia_models.dart';
import '../../data/repositories/wikimapia_repository.dart';
import '../../data/utils/measurement_utils.dart';

class WikimapiaController extends ChangeNotifier {
  WikimapiaController({
    WikimapiaRepository? repository,
    this.onError,
  }) : _repository = repository ?? WikimapiaRepository();

  final WikimapiaRepository _repository;
  final ValueChanged<String>? onError;

  final List<String> _wikimapiaTags = <String>[];
  final Map<String, WikimapiaObject> _wikimapiaObjectsMap =
      <String, WikimapiaObject>{};
  final Map<int, WikimapiaPlace> _wikimapiaPlaceCache = <int, WikimapiaPlace>{};
  final Map<String, List<LatLng>> _wikimapiaPolygonMap =
      <String, List<LatLng>>{};
  List<WikimapiaObject> _wikimapiaObjects = const <WikimapiaObject>[];
  List<List<LatLng>> _wikimapiaPolygonData = const <List<LatLng>>[];
  bool _isLoadingWikimapia = false;
  int _wikimapiaRequestGeneration = 0;
  String? _activeWikimapiaId;
  Timer? _wikimapiaDebounce;
  bool _enabled = false;

  List<String> get tags => List<String>.unmodifiable(_wikimapiaTags);
  List<WikimapiaObject> get objects => _wikimapiaObjects;
  List<List<LatLng>> get polygonData => _wikimapiaPolygonData;
  Map<String, List<LatLng>> get polygonMap =>
      Map<String, List<LatLng>>.unmodifiable(_wikimapiaPolygonMap);
  bool get isLoading => _isLoadingWikimapia;
  String? get activeId => _activeWikimapiaId;
  bool get enabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _wikimapiaRequestGeneration++;
      _wikimapiaObjects = const <WikimapiaObject>[];
      _wikimapiaPolygonData = const <List<LatLng>>[];
      _activeWikimapiaId = null;
    }
    notifyListeners();
  }

  void setTags(Iterable<String> values) {
    _wikimapiaTags
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void scheduleLoad(LatLngBounds bounds) {
    _wikimapiaDebounce?.cancel();
    if (!_enabled) return;
    _wikimapiaDebounce = Timer(
      const Duration(milliseconds: 600),
      () => loadObjects(bounds),
    );
  }

  Future<void> loadObjects(
    LatLngBounds bounds, {
    bool clearPrevious = false,
  }) async {
    if (!_enabled) return;
    final generation = ++_wikimapiaRequestGeneration;
    _isLoadingWikimapia = true;
    notifyListeners();
    try {
      final roundedBounds = LatLngBounds(
        LatLng(
          double.parse(bounds.south.toStringAsFixed(5)),
          double.parse(bounds.west.toStringAsFixed(5)),
        ),
        LatLng(
          double.parse(bounds.north.toStringAsFixed(5)),
          double.parse(bounds.east.toStringAsFixed(5)),
        ),
      );
      var places = await _repository.getPlacesByBox(
        bounds: roundedBounds,
        count: 100,
      );
      places = await Future.wait(places.map((place) async {
        if (_wikimapiaPlaceCache.containsKey(place.id) || place.detailsLoaded) {
          return place;
        }
        try {
          return await _repository.getPlaceById(place.id);
        } catch (_) {
          return place;
        }
      }));
      if (!_enabled || generation != _wikimapiaRequestGeneration) return;
      if (clearPrevious) {
        _wikimapiaObjectsMap.clear();
        _wikimapiaPolygonMap.clear();
        _wikimapiaPlaceCache.clear();
      }
      for (final place in places) {
        if (place.id <= 0 || !place.hasValidLocation) continue;
        _wikimapiaPlaceCache[place.id] = place;
        final object = WikimapiaObject(
          id: place.id.toString(),
          title: place.title,
          description: place.description,
          position: place.location,
          tags: place.categories.map((category) => category.title).toList(),
        );
        _wikimapiaObjectsMap[object.id] = object;
        if (place.polygon.length >= 3) {
          _wikimapiaPolygonMap[object.id] = place.polygon;
        }
      }
      final center = bounds.center;
      final sorted = _wikimapiaObjectsMap.values.toList()
        ..sort((a, b) => MeasurementUtils.calculateDistance(center, a.position)
            .compareTo(MeasurementUtils.calculateDistance(center, b.position)));
      _wikimapiaObjects = sorted.take(300).toList(growable: false);
      _wikimapiaPolygonData =
          _wikimapiaPolygonMap.values.toList(growable: false);
      notifyListeners();
    } on WikimapiaRequestCancelledException {
      return;
    } catch (error) {
      onError?.call(error.toString());
    } finally {
      if (generation == _wikimapiaRequestGeneration) {
        _isLoadingWikimapia = false;
        notifyListeners();
      }
    }
  }

  void setActiveId(String id) {
    _activeWikimapiaId = id;
    notifyListeners();
  }

  Future<WikimapiaPlace?> showObjectDetails(int id) async {
    if (id <= 0) return null;
    final cached = _wikimapiaPlaceCache[id];
    if (cached?.detailsLoaded ?? false) return cached;
    final fetched = await _repository.getPlaceById(id);
    _wikimapiaPlaceCache[id] = fetched;
    return fetched;
  }

  @override
  void dispose() {
    _wikimapiaDebounce?.cancel();
    super.dispose();
  }
}
