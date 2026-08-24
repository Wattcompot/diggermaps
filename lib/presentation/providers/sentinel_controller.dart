import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:http/http.dart' as http;

import '../../data/repositories/sentinel_repository.dart';

class SentinelController extends ChangeNotifier {
  SentinelController({
    required this.visibleBounds,
    SentinelRepository? repository,
    this.onError,
    this.onCalendarRequested,
  }) : _repository = repository ?? SentinelRepository() {
    _sentinelTileProvider = _createTileProvider();
  }

  final LatLngBounds Function() visibleBounds;
  final SentinelRepository _repository;
  final ValueChanged<String>? onError;
  final VoidCallback? onCalendarRequested;

  DateTime _spectralDate = DateTime.now();
  DateTimeRange? _spectralDateRange;
  double _cloudCoverage = 20;
  double _spectralImageCloudCoverage = 20;
  Timer? _sentinelDebounce;
  int _sentinelRequestGeneration = 0;
  String? _sentinelTileUrl;
  bool _sentinelLoading = false;
  bool _visible = false;
  http.Client? _sentinelHttpClient;
  late TileProvider _sentinelTileProvider;
  int _spectralLayerVersion = 0;
  final Map<String, List<SentinelDateInfo>> _sentinelDatesByArea =
      <String, List<SentinelDateInfo>>{};

  DateTime get date => _spectralDate;
  DateTimeRange? get dateRange => _spectralDateRange;
  double get cloudCoverage => _cloudCoverage;
  double get imageCloudCoverage => _spectralImageCloudCoverage;
  String? get tileUrl => _sentinelTileUrl;
  bool get loading => _sentinelLoading;
  bool get visible => _visible;
  TileProvider get tileProvider => _sentinelTileProvider;
  int get layerVersion => _spectralLayerVersion;
  Map<String, List<SentinelDateInfo>> get datesByArea =>
      Map<String, List<SentinelDateInfo>>.unmodifiable(_sentinelDatesByArea);

  void showCalendar() => onCalendarRequested?.call();

  Future<List<SentinelDateInfo>> loadDatesForVisibleArea() async {
    final bbox = _bbox;
    final key = bbox.map((value) => value.toStringAsFixed(3)).join(',');
    final cached = _sentinelDatesByArea[key];
    if (cached != null && cached.isNotEmpty) return cached;
    final dates = await _repository.queryDates(
      bbox: bbox,
      from: DateTime(2015, 6, 23),
      to: DateTime.now(),
    );
    if (dates.isNotEmpty) {
      _sentinelDatesByArea[key] = List<SentinelDateInfo>.unmodifiable(dates);
    }
    return dates;
  }

  Future<void> applyDate(
    DateTime date, {
    double? maxCloudCoverage,
    double? imageCloudCoverage,
  }) async {
    _spectralDate = date;
    _spectralDateRange = DateTimeRange(
      start: date,
      end: date.add(const Duration(days: 1)),
    );
    _cloudCoverage = maxCloudCoverage ?? _cloudCoverage;
    _spectralImageCloudCoverage =
        imageCloudCoverage ?? _spectralImageCloudCoverage;
    _sentinelTileUrl = null;
    _sentinelLoading = true;
    _visible = true;
    notifyListeners();
    await refreshTile();
  }

  void scheduleRefresh() {
    _sentinelDebounce?.cancel();
    if (!_visible) return;
    _sentinelDebounce = Timer(
      const Duration(milliseconds: 500),
      refreshTile,
    );
  }

  Future<void> refreshTile() async {
    if (!_visible) return;
    final generation = ++_sentinelRequestGeneration;
    try {
      final url = await _repository.getTileUrl(
        date: _spectralDate,
        dateFrom: _spectralDateRange?.start,
        dateTo: _spectralDateRange?.end,
        cloudCoverage: _cloudCoverage,
        preset: SpectralPreset.naturalColor,
        bbox: _bbox,
      );
      if (generation != _sentinelRequestGeneration) return;
      if (_sentinelTileUrl != url) {
        _sentinelTileProvider = _createTileProvider();
        _spectralLayerVersion++;
      }
      _sentinelTileUrl = url;
      _sentinelLoading = false;
      notifyListeners();
    } catch (error) {
      if (generation != _sentinelRequestGeneration) return;
      _sentinelLoading = false;
      notifyListeners();
      onError?.call(error is NoImageryException
          ? 'Нет спутниковых снимков за выбранный период'
          : 'Не удалось получить снимки');
    }
  }

  void hideImagery() {
    _sentinelRequestGeneration++;
    _sentinelDebounce?.cancel();
    _visible = false;
    _sentinelTileUrl = null;
    _sentinelLoading = false;
    notifyListeners();
  }

  List<double> get _bbox {
    final bounds = visibleBounds();
    return <double>[bounds.west, bounds.south, bounds.east, bounds.north];
  }

  TileProvider _createTileProvider() {
    if (kIsWeb) {
      return NetworkTileProvider(
        abortObsoleteRequests: true,
        silenceExceptions: true,
      );
    }
    _sentinelHttpClient ??= http.Client();
    return FMTCTileProvider(
      stores: const <String, BrowseStoreStrategy>{
        'sentinelStore': BrowseStoreStrategy.readUpdateCreate,
      },
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
      cachedValidDuration: const Duration(days: 30),
      recordHitsAndMisses: false,
      httpClient: _sentinelHttpClient,
    );
  }

  @override
  void dispose() {
    _sentinelDebounce?.cancel();
    _sentinelHttpClient?.close();
    super.dispose();
  }
}
