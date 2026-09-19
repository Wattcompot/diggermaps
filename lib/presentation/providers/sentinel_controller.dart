import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:http/http.dart' as http;

import '../../data/repositories/sentinel_repository.dart';
import '../../services/tile_cache/retained_tile_provider.dart';

/// Один отображаемый набор снимков (одна дата / одна мозаика).
///
/// [dateKey] — идентичность картинки: панорама и зум её не меняют, смена даты
/// меняет. Ключ слоя строится по [dateKey], а НЕ по URL, иначе каждая новая
/// мозаика (и каждый pan) уничтожала бы слой вместе с загруженными тайлами.
@immutable
class SentinelImagery {
  const SentinelImagery({
    required this.urlTemplate,
    required this.dateKey,
    this.minNativeZoom = 0,
    this.maxNativeZoom,
    this.tileDimension = 256,
  });

  final String urlTemplate;
  final String dateKey;

  /// Лимиты зума самого источника (TileJSON).
  final int minNativeZoom;
  final int? maxNativeZoom;
  final int tileDimension;

  /// Идентичность картинки: дата + URL мозаики.
  ///
  /// Из неё строится `key` слоя. Меняется URL при той же дате (панорама вышла
  /// за покрытие) — это тоже другая картинка, и ей нужен свой слой, иначе
  /// `TileLayer` уйдёт в `reloadImages()` и перезагрузит уже загруженные тайлы.
  String get id => '$dateKey|$urlTemplate';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SentinelImagery &&
          other.urlTemplate == urlTemplate &&
          other.dateKey == dateKey &&
          other.minNativeZoom == minNativeZoom &&
          other.maxNativeZoom == maxNativeZoom &&
          other.tileDimension == tileDimension);

  @override
  int get hashCode => Object.hash(
      urlTemplate, dateKey, minNativeZoom, maxNativeZoom, tileDimension);
}

class SentinelController extends ChangeNotifier {
  SentinelController({
    required this.visibleBounds,
    SentinelRepository? repository,
    this.onError,
    this.onCalendarRequested,
    this.retainedImageryTtl = const Duration(seconds: 4),
    this.retainedImageryGrace = const Duration(milliseconds: 400),
  }) : _repository = repository ?? SentinelRepository() {
    // Провайдер создаётся ровно один раз и живёт до dispose контроллера.
    // Раньше он пересоздавался при каждом изменении URL, что убивало сессию
    // ImageCache и заставляло перезагружать все тайлы.
    _innerTileProvider = _createTileProvider();
    _tileProvider = RetainedTileProvider(_innerTileProvider);
  }

  final LatLngBounds Function() visibleBounds;
  final SentinelRepository _repository;
  final ValueChanged<String>? onError;
  final VoidCallback? onCalendarRequested;

  /// Жёсткий предел удержания предыдущей картинки: если новая так и не
  /// отрисовалась, старый слой снимается по этому таймауту.
  final Duration retainedImageryTtl;

  /// Сколько держать предыдущую картинку после того, как новая показала первый
  /// реально загруженный тайл (первого тайла недостаточно для полной картинки).
  final Duration retainedImageryGrace;

  DateTime _spectralDate = DateTime.now();
  DateTimeRange? _spectralDateRange;
  double _cloudCoverage = 20;
  double _spectralImageCloudCoverage = 20;
  Timer? _sentinelDebounce;
  Timer? _retainedImageryTimer;
  Timer? _retainedRemovalTimer;
  int _sentinelRequestGeneration = 0;
  int _imageryGeneration = 0;
  SentinelImagery? _imagery;
  SentinelImagery? _retainedImagery;
  bool _imageryDisplayed = false;
  bool _sentinelLoading = false;
  bool _visible = false;
  bool _disposed = false;
  http.Client? _sentinelHttpClient;
  late final TileProvider _innerTileProvider;
  late final RetainedTileProvider _tileProvider;
  final Map<String, List<SentinelDateInfo>> _sentinelDatesByArea =
      <String, List<SentinelDateInfo>>{};

  static const int _maxDatesCacheEntries = 16;

  DateTime get date => _spectralDate;
  DateTimeRange? get dateRange => _spectralDateRange;
  double get cloudCoverage => _cloudCoverage;
  double get imageCloudCoverage => _spectralImageCloudCoverage;

  /// Текущая картинка (загруженная или ожидаемая дата).
  SentinelImagery? get imagery => _imagery;

  /// Предыдущая картинка, которую держим под новой, пока та грузится.
  SentinelImagery? get retainedImagery => _retainedImagery;

  String? get tileUrl => _imagery?.urlTemplate;

  /// Дата картинки, которая сейчас на карте (а не выбранная в календаре).
  ///
  /// UI должен подписывать снимок этим значением: пока новая дата грузится,
  /// на карте остаётся предыдущая картинка, и «старая дата с новым ярлыком»
  /// недопустима.
  DateTime? get imageryDate {
    final key = _imagery?.dateKey;
    return key == null ? null : DateTime.tryParse(key);
  }

  /// Текущая картинка реально отрисовалась (есть декодированный тайл).
  bool get imageryDisplayed => _imageryDisplayed;

  bool get loading => _sentinelLoading;
  bool get visible => _visible;

  /// Стабильный провайдер: не меняется ни при pan/zoom, ни при смене даты*.
  /// (*URL меняется, но провайдер — нет: смена URL идёт через
  /// `TileLayer.didUpdateWidget` → `reloadImages`, с переиспользованием
  /// объектов TileImage, а не через dispose состояния слоя.)
  TileProvider get tileProvider => _tileProvider;

  /// Идентичность картинки (дата). Растёт только при смене даты.
  int get layerVersion => _imageryGeneration;

  Map<String, List<SentinelDateInfo>> get datesByArea =>
      Map<String, List<SentinelDateInfo>>.unmodifiable(_sentinelDatesByArea);

  void showCalendar() => onCalendarRequested?.call();

  Future<List<SentinelDateInfo>> loadDatesForVisibleArea() async {
    final bbox = _bboxOrNull;
    if (bbox == null) return const <SentinelDateInfo>[];
    final key = bbox.map((value) => value.toStringAsFixed(3)).join(',');
    final cached = _sentinelDatesByArea[key];
    if (cached != null && cached.isNotEmpty) return cached;
    final dates = await _repository.queryDates(
      bbox: bbox,
      from: DateTime(2015, 6, 23),
      to: DateTime.now(),
    );
    if (_disposed) return dates;
    if (dates.isNotEmpty) {
      _sentinelDatesByArea[key] = List<SentinelDateInfo>.unmodifiable(dates);
      while (_sentinelDatesByArea.length > _maxDatesCacheEntries) {
        _sentinelDatesByArea.remove(_sentinelDatesByArea.keys.first);
      }
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
    _visible = true;
    if (_imagery == null || _imagery!.dateKey != _dateKey(date)) {
      // Запрошена другая дата: показываем прогресс сразу, но камеру/картинку
      // не трогаем — новая картинка появится только когда её URL получен,
      // и до этого на карте честно остаётся предыдущая (см. imageryDate).
      _sentinelLoading = true;
    }
    _notify();
    await refreshTile();
  }

  /// Вызывается слоем, когда у текущей картинки появился **реально
  /// загруженный** тайл (декодированное изображение, не «тайл в загрузке»).
  ///
  /// Снимает retained-слой через короткий grace-период, и никогда — раньше
  /// первого загруженного тайла (иначе была бы маскировка пустоты).
  void markImageryDisplayed() {
    if (_disposed) return;
    if (_imageryDisplayed && _retainedImagery == null) return;
    _imageryDisplayed = true;
    _sentinelLoading = false;
    if (_retainedImagery != null) {
      _retainedRemovalTimer?.cancel();
      _retainedRemovalTimer = Timer(retainedImageryGrace, _dropRetainedImagery);
    }
    _notify();
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
    if (!_visible || _disposed) return;
    final bbox = _bboxOrNull;
    if (bbox == null) return;
    final generation = ++_sentinelRequestGeneration;
    final targetDate = _spectralDate;
    try {
      final source = await _repository.getTileSource(
        date: targetDate,
        dateFrom: _spectralDateRange?.start,
        dateTo: _spectralDateRange?.end,
        cloudCoverage: _cloudCoverage,
        preset: SpectralPreset.naturalColor,
        bbox: bbox,
      );
      if (generation != _sentinelRequestGeneration || _disposed) return;
      final next = SentinelImagery(
        urlTemplate: source.urlTemplate,
        dateKey: _dateKey(targetDate),
        minNativeZoom: source.minZoom,
        maxNativeZoom: source.maxZoom,
        tileDimension: source.tileDimension,
      );
      if (next.id == _imagery?.id) {
        // Тот же URL той же даты: слой уже есть, тайлы перезагружать нечего.
        // Прогресс снимет markImageryDisplayed, когда тайл реально загрузится.
        return;
      }
      final dateChanged = next.dateKey != _imagery?.dateKey;
      // Смена идентичности: новая дата ИЛИ другой URL мозаики (панорама вышла
      // за покрытие). Предыдущая картинка уходит в retained-слой со своим
      // key/URL — она остаётся видимой, пока новая реально не загрузится.
      _retain(_imagery);
      _imagery = next;
      _imageryDisplayed = false;
      _sentinelLoading = true;
      if (dateChanged) _imageryGeneration++;
      _notify();
    } catch (error) {
      if (generation != _sentinelRequestGeneration || _disposed) return;
      _sentinelLoading = false;
      _notify();
      onError?.call(error is NoImageryException
          ? 'Нет спутниковых снимков за выбранный период'
          : 'Не удалось получить снимки');
    }
  }

  void hideImagery() {
    _sentinelRequestGeneration++;
    _sentinelDebounce?.cancel();
    _retainedImageryTimer?.cancel();
    _retainedImageryTimer = null;
    _retainedRemovalTimer?.cancel();
    _retainedRemovalTimer = null;
    _visible = false;
    _imagery = null;
    _retainedImagery = null;
    _imageryDisplayed = false;
    _sentinelLoading = false;
    _notify();
  }

  /// Удерживает предыдущую картинку под новой. Максимум один слой: новый
  /// вызов отменяет предыдущее удержание.
  void _retain(SentinelImagery? imagery) {
    _retainedRemovalTimer?.cancel();
    _retainedRemovalTimer = null;
    _retainedImageryTimer?.cancel();
    _retainedImageryTimer = null;
    _retainedImagery = imagery;
    if (imagery == null) return;
    _retainedImageryTimer = Timer(retainedImageryTtl, _dropRetainedImagery);
  }

  void _dropRetainedImagery() {
    _retainedImageryTimer?.cancel();
    _retainedImageryTimer = null;
    _retainedRemovalTimer?.cancel();
    _retainedRemovalTimer = null;
    if (_retainedImagery == null) return;
    _retainedImagery = null;
    _notify();
  }

  List<double>? get _bboxOrNull {
    try {
      final bounds = visibleBounds();
      return <double>[bounds.west, bounds.south, bounds.east, bounds.north];
    } catch (_) {
      // Карта ещё не отрисована — запрос отложится до следующего refresh.
      return null;
    }
  }

  static String _dateKey(DateTime date) {
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
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

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sentinelDebounce?.cancel();
    _retainedImageryTimer?.cancel();
    _retainedRemovalTimer?.cancel();
    final client = _sentinelHttpClient;
    _sentinelHttpClient = null;
    final provider = _innerTileProvider;
    if (provider is FMTCTileProvider) {
      // Не закрываем клиент, пока FMTC дочитывает тайлы: http.Client.close()
      // во время активных запросов даёт ClientException в самих тайлах.
      unawaited(provider.dispose().whenComplete(() => client?.close()));
    } else {
      provider.dispose();
      client?.close();
    }
    super.dispose();
  }
}
