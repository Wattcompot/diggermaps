import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ВРЕМЕННАЯ диагностика пути GPS-маячка. По умолчанию ВЫКЛЮЧЕНА — обычный
/// билд не меняется. Чтобы увидеть, на каком звене теряется позиция, соберите
/// с `--dart-define=GPS_DEBUG=true` и снимите logcat по метке `[GPS]`.
/// После локализации причины этот блок и все вызовы `_gpsLog` удаляются.
const bool _kGpsDebug = bool.fromEnvironment('GPS_DEBUG');

void _gpsLog(String message) {
  if (_kGpsDebug) debugPrint('[GPS] $message');
}

/// Абстракция над платформенной геолокацией.
///
/// Нужна, чтобы поведение при старте (сохранённая камера / GPS / разрешения)
/// тестировалось без плагинов и без платформенных каналов.
abstract class LocationDataSource {
  Future<bool> isServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  /// Последняя известная позиция.
  ///
  /// На Windows/в вебе метод может быть не поддержан: реализация обязана
  /// вернуть `null`, а не бросить исключение наружу.
  Future<Position?> lastKnownPosition();

  /// Текущая позиция. Может бросить `TimeoutException` /
  /// `LocationServiceDisabledException` / `PermissionDeniedException`.
  Future<Position> currentPosition();

  /// Непрерывный поток позиций для слоя маячка.
  ///
  /// Реализация должна вернуть поток, а не бросать синхронно: если платформа
  /// не поддерживает стрим, ошибка приходит событием внутри потока.
  Stream<Position> positionStream();
}

class GeolocatorLocationDataSource implements LocationDataSource {
  const GeolocatorLocationDataSource();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position?> lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      // UnsupportedError / MissingPluginException / PlatformException.
      return null;
    }
  }

  @override
  Future<Position> currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

  @override
  Stream<Position> positionStream() {
    try {
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1,
        ),
      );
    } catch (error, stackTrace) {
      // UnsupportedError / MissingPluginException: слой маячка обработает
      // ошибку как отсутствие позиции, а не упадёт при построении.
      return Stream<Position>.error(error, stackTrace);
    }
  }
}

/// Сохранённое положение камеры.
@immutable
class MapCameraSnapshot {
  const MapCameraSnapshot({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    this.rotation = 0,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double rotation;

  LatLng get center => LatLng(latitude, longitude);

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      zoom.isFinite &&
      rotation.isFinite &&
      latitude.abs() <= 85.0511287798 &&
      longitude.abs() <= 180 &&
      zoom >= 0 &&
      zoom <= 30;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MapCameraSnapshot &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.zoom == zoom &&
          other.rotation == rotation);

  @override
  int get hashCode => Object.hash(latitude, longitude, zoom, rotation);
}

abstract class MapCameraStore {
  Future<MapCameraSnapshot?> load();

  Future<void> save(MapCameraSnapshot snapshot);
}

/// Хранилище камеры в SharedPreferences.
///
/// Ключи новые (`map_camera_*`); существующие ключи приложения
/// (`theme_mode`, `search_history`, `spectral_cache_cleanup_days`, …) не
/// читаются и не изменяются.
class SharedPreferencesMapCameraStore implements MapCameraStore {
  const SharedPreferencesMapCameraStore();

  static const String latitudeKey = 'map_camera_latitude';
  static const String longitudeKey = 'map_camera_longitude';
  static const String zoomKey = 'map_camera_zoom';
  static const String rotationKey = 'map_camera_rotation';
  static const String savedAtKey = 'map_camera_saved_at';

  @override
  Future<MapCameraSnapshot?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final latitude = _readDouble(preferences, latitudeKey);
      final longitude = _readDouble(preferences, longitudeKey);
      final zoom = _readDouble(preferences, zoomKey);
      if (latitude == null || longitude == null || zoom == null) return null;
      final snapshot = MapCameraSnapshot(
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        rotation: _readDouble(preferences, rotationKey) ?? 0,
      );
      return snapshot.isValid ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(MapCameraSnapshot snapshot) async {
    if (!snapshot.isValid) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble(latitudeKey, snapshot.latitude);
      await preferences.setDouble(longitudeKey, snapshot.longitude);
      await preferences.setDouble(zoomKey, snapshot.zoom);
      await preferences.setDouble(rotationKey, snapshot.rotation);
      await preferences.setInt(
        savedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Кэш камеры не критичен: ошибку записи не показываем.
    }
  }

  static double? _readDouble(SharedPreferences preferences, String key) {
    final value = preferences.get(key);
    if (value is num) return value.toDouble();
    return null;
  }
}

class LocationController extends ChangeNotifier {
  LocationController({
    required MapController mapController,
    required ValueChanged<String> onMessage,
    LocationDataSource? dataSource,
    MapCameraStore? cameraStore,
    void Function(LatLng center, double zoom)? moveSink,
    this.locationZoom = 17,
    this.persistenceDebounce = const Duration(milliseconds: 800),
    this.lastKnownMaxAge = const Duration(minutes: 5),
  })  : _mapController = mapController,
        _onMessage = onMessage,
        _dataSource = dataSource ?? const GeolocatorLocationDataSource(),
        _cameraStore = cameraStore ?? const SharedPreferencesMapCameraStore(),
        _moveSink = moveSink {
    // Загрузка камеры стартует сразу, но не блокирует UI.
    unawaited(_loadSavedCamera());
  }

  final MapController _mapController;
  final ValueChanged<String> _onMessage;
  final LocationDataSource _dataSource;
  final MapCameraStore _cameraStore;
  final void Function(LatLng center, double zoom)? _moveSink;

  /// Зум, на который переходим при центрировании по геопозиции.
  final double locationZoom;

  /// Задержка записи камеры: панорама/зум не пишут на диск каждый кадр.
  final Duration persistenceDebounce;

  /// Насколько «свежей» должна быть последняя известная позиция, чтобы её
  /// можно было использовать без запроса текущей.
  final Duration lastKnownMaxAge;

  bool _followLocation = false;
  bool _locationLayerEnabled = false;
  bool _mapReady = false;
  bool _disposed = false;
  bool _savedCameraLoaded = false;
  bool _startupRequested = false;
  bool _cameraEstablished = false;
  MapCameraSnapshot? _savedCamera;
  MapCameraSnapshot? _pendingCamera;
  Timer? _persistDebounce;
  int _gestureGeneration = 0;

  bool get followLocation => _followLocation;
  bool get locationLayerEnabled => _locationLayerEnabled;

  /// Один общий поток позиций для слоя маячка.
  ///
  /// Создаётся лениво и один раз (идентичность сохраняется между пересборками
  /// карты — см. `LocationMarkerStream`), а сам контроллер живёт до `dispose`.
  ///
  /// Важно: сюда обращается `build` карты на ПЕРВОЙ отрисовке — то есть ещё до
  /// выдачи разрешения на геолокацию. Поэтому геттер создаёт только контроллер
  /// и НЕ подписывается на geolocator: подписка без разрешения немедленно
  /// завершается ошибкой и `onDone`, после чего источник мёртв навсегда, а
  /// мемоизация (`_positionStream ??=`) уже не даёт его пересоздать — маячок
  /// не появляется и не двигается. Живой источник поднимает
  /// [_ensureLivePositionSource] уже ПОСЛЕ подтверждённого разрешения.
  Stream<Position> get positionStream =>
      _positionStream ??= _ensureController().stream;
  Stream<Position>? _positionStream;
  StreamController<Position>? _positionController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;

  /// Жива ли подписка на непрерывный источник позиций.
  ///
  /// Помечается `false` при закрытии источника (`onDone`) и в [dispose], чтобы
  /// следующее включение слоя переподписалось вместо тишины.
  bool _sourceLive = false;

  /// Гарантирует существование общего broadcast-контроллера позиций.
  ///
  /// Контроллер создаётся один раз и живёт до [dispose]; каждый новый слушатель
  /// (в т. ч. после пересборки слоя) сразу получает последнюю известную позицию
  /// через `onListen`, поэтому маячок появляется мгновенно, не дожидаясь нового
  /// GPS-события (телефон в покое может молчать минутами). Здесь НЕ подписываемся
  /// на geolocator — см. [positionStream].
  StreamController<Position> _ensureController() {
    final existing = _positionController;
    if (existing != null && !existing.isClosed) return existing;
    final controller = StreamController<Position>.broadcast(
      onListen: _replayLastPosition,
    );
    _positionController = controller;
    return controller;
  }

  /// (Пере)подписывается на непрерывный поток геолокации, направляя события в
  /// тот же самый [_positionController]. Идемпотентно: если подписка жива —
  /// ничего не делает.
  ///
  /// Вызывается только после подтверждённого разрешения (см.
  /// [enableLocationLayer], [_locateAndMove]). Если источник завершится (Android
  /// закрывает поток при отзыве разрешения / выключении сервиса), подписка
  /// помечается мёртвой в `onDone`, и следующее включение слоя (например, на
  /// resume) переподпишется — без второго слушателя, контроллера или
  /// параллельной системы позиционирования.
  void _ensureLivePositionSource() {
    if (_disposed || _sourceLive) return;
    final controller = _ensureController();
    if (controller.isClosed) return;
    _positionSubscription?.cancel();
    _sourceLive = true;
    _gpsLog('_ensureLivePositionSource: подписка на geolocator создана');
    _positionSubscription = _dataSource.positionStream().listen(
      (position) {
        if (_isValidPosition(position)) _lastPosition = position;
        if (!controller.isClosed) controller.add(position);
        _gpsLog('source: позиция ${position.latitude},${position.longitude} '
            '→ в поток');
      },
      onError: (Object error) {
        _gpsLog('source: ошибка потока $error (маячок держит последнюю)');
        // Ошибка потока (сервис выключили, разрешение отозвали) не должна
        // гасить маячок: последняя известная позиция остаётся на карте, а
        // новые события придут, когда геолокация вернётся.
      },
      onDone: () {
        _gpsLog(
            'source: поток закрылся (onDone) — переармим при след. включении');
        // Источник закрылся (обычно отзыв разрешения / выключение сервиса на
        // Android). Помечаем подписку мёртвой, чтобы следующее включение слоя
        // переподписалось на живой источник вместо тишины.
        _sourceLive = false;
      },
      cancelOnError: false,
    );
  }

  void _replayLastPosition() {
    final last = _lastPosition;
    final controller = _positionController;
    if (last == null || controller == null || controller.isClosed) {
      _gpsLog('onListen: новый подписчик, но повторять нечего '
          '(last=${last != null})');
      return;
    }
    _gpsLog('onListen: повторяем последнюю позицию новому подписчику слоя');
    controller.add(last);
  }

  /// Включить слой маячка без перемещения камеры.
  ///
  /// Вызывается при старте после проверки разрешения — независимо от того,
  /// есть ли сохранённая камера. Раньше слой включался только внутри
  /// `_locateAndMove`, и при сохранённой камере маячок не появлялся вовсе.
  ///
  /// Ранний выход был убран сознательно: метод вызывается и на каждом resume,
  /// когда непрерывный источник мог умереть (Android закрывает поток при
  /// сворачивании / отзыве разрешения). Поэтому здесь всегда переармливаем
  /// источник (идемпотентно) и досылаем свежий фикс — иначе маячок после
  /// возврата в приложение застыл бы или пропал.
  Future<void> enableLocationLayer() async {
    if (_disposed) return;
    _gpsLog('enableLocationLayer: старт (layerEnabled=$_locationLayerEnabled)');
    if (!await handleLocationPermission(silent: true) || _disposed) {
      _gpsLog('enableLocationLayer: разрешение/сервис не даны — выходим');
      return;
    }
    if (!_locationLayerEnabled) {
      _locationLayerEnabled = true;
      _notify();
      _gpsLog('enableLocationLayer: слой включён, notify отправлен');
    }
    // Разрешение подтверждено — теперь безопасно поднять живой источник.
    // Непрерывный поток отдаёт позицию лишь при движении, а до выдачи
    // разрешения источник не поднимался вовсе. Досылаем свежий фикс в тот же
    // существующий контроллер — без нового слушателя и без второй системы
    // позиционирования, иначе на неподвижном устройстве маячок не появится,
    // пока его не сдвинут.
    _ensureLivePositionSource();
    unawaited(_pushFreshFix());
  }

  /// Разово запрашивает позицию и досылает её в текущий поток маячка.
  ///
  /// В отличие от [_seedInitialPosition] не одноразовый: вызывается в момент,
  /// когда слой включается (например, после выдачи разрешения на resume).
  /// Работает поверх уже созданного [_positionController]; если поток ещё не
  /// создан, первичный seed при первой подписке закроет разрыв сам.
  Future<void> _pushFreshFix() async {
    if (_disposed) return;
    final controller = _positionController;
    if (controller == null || controller.isClosed) return;
    final Position? position;
    try {
      position = await _resolvePosition();
    } catch (_) {
      return;
    }
    if (_disposed || position == null || !_isValidPosition(position)) {
      _gpsLog('_pushFreshFix: фикс не получен (null/невалидно)');
      return;
    }
    _lastPosition = position;
    if (!controller.isClosed) controller.add(position);
    _gpsLog('_pushFreshFix: свежий фикс ${position.latitude},'
        '${position.longitude} досланы в поток');
  }

  /// Сохранённая камера (если есть и валидна).
  MapCameraSnapshot? get savedCamera => _savedCamera;

  /// Выполнена ли попытка чтения префов (нужно, чтобы отличать
  /// «камеры нет» от «ещё не прочитали»).
  bool get savedCameraLoaded => _savedCameraLoaded;

  /// Менял ли пользователь камеру вручную (с тех пор, как карта готова).
  bool get hasUserGesture => _gestureGeneration > 0;

  Future<void> _loadSavedCamera() async {
    final loaded = await _cameraStore.load();
    if (_disposed) return;
    _savedCameraLoaded = true;
    if (loaded != null && loaded.isValid) {
      _savedCamera = loaded;
      // Приоритет сохранённой камеры: если карта уже отрисована — применяем,
      // но никогда не перебиваем жест пользователя.
      if (_mapReady && _gestureGeneration == 0) {
        _moveCamera(loaded.center, loaded.zoom, rotation: loaded.rotation);
      }
      // Камера восстановлена из кэша → GPS не двигает карту, но маячок
      // всё равно должен быть виден.
      if (_mapReady) unawaited(enableLocationLayer());
    } else if (_mapReady && !hasUserGesture) {
      unawaited(centerOnStartup());
    }
    _notify();
  }

  /// Вызывается из `MapOptions.onMapReady`.
  ///
  /// Пока префы не прочитаны — камеру не трогаем (иначе возможен «прыжок»),
  /// при появлении сохранённой камеры она применится из [_loadSavedCamera].
  void restoreCameraOnReady() {
    if (_disposed) return;
    _mapReady = true;
    final saved = _savedCamera;
    if (saved != null && saved.isValid) {
      _moveCamera(saved.center, saved.zoom, rotation: saved.rotation);
      unawaited(enableLocationLayer());
      return;
    }
    if (!_savedCameraLoaded) return;
    // Сохранённой камеры нет — единственный случай, когда можно центрировать
    // карту по геопозиции (никакого «московского» фолбэка).
    // Слой маячка включит сам `_locateAndMove`.
    unawaited(centerOnStartup());
  }

  Future<void> centerOnLocation() async {
    if (_followLocation) return;
    if (!await handleLocationPermission()) return;
    await _locateAndMove(follow: true);
  }

  Future<void> centerOnceOnLocation() async {
    if (!await handleLocationPermission()) return;
    await _locateAndMove(follow: false);
  }

  /// Центрирование по геопозиции при старте.
  ///
  /// Ничего не делает, если есть сохранённая камера: она имеет приоритет.
  Future<void> centerOnStartup() async {
    if (_disposed || !_mapReady || !_savedCameraLoaded || _startupRequested) {
      return;
    }
    if (hasUserGesture || _savedCamera != null) {
      // Камеру не трогаем, но маячок показать надо.
      unawaited(enableLocationLayer());
      return;
    }
    _startupRequested = true;
    final generation = _gestureGeneration;
    if (!await handleLocationPermission() || _disposed) return;
    if (generation != _gestureGeneration) {
      if (!_locationLayerEnabled) {
        _locationLayerEnabled = true;
        _notify();
      }
      // Разрешение подтверждено, но пользователь уже двигал карту: камеру не
      // перехватываем, однако живой источник поднимаем — маячок должен быть.
      _ensureLivePositionSource();
      unawaited(_pushFreshFix());
      return;
    }
    await _locateAndMove(follow: false);
  }

  /// Пользователь сам подвигал карту.
  ///
  /// Увеличивает поколение жестов: незавершённый GPS-фикс больше не будет
  /// перехватывать управление.
  void onUserGesture() {
    _gestureGeneration++;
    if (_followLocation) {
      _followLocation = false;
      _notify();
    }
  }

  void stopFollowLocation() {
    if (!_followLocation) return;
    _followLocation = false;
    _notify();
  }

  /// Вызывается при изменении камеры (в том числе программном).
  ///
  /// Запись в префы дебаунсится, чтобы панорама не писала на диск каждый кадр.
  void onCameraChanged(MapCamera camera, {required bool hasGesture}) {
    if (_disposed) return;
    // Не сохраняем нейтральную стартовую камеру как позицию пользователя.
    if (hasGesture) _cameraEstablished = true;
    if (!_cameraEstablished) return;
    final snapshot = MapCameraSnapshot(
      latitude: camera.center.latitude,
      longitude: camera.center.longitude,
      zoom: camera.zoom,
      rotation: camera.rotation,
    );
    if (!snapshot.isValid) return;
    _pendingCamera = snapshot;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(persistenceDebounce, _persistCamera);
  }

  /// Проверка сервиса и разрешения на геолокацию.
  ///
  /// При [silent] пользовательские сообщения не показываются — режим для
  /// фонового включения слоя маячка при старте, чтобы не спамить снекбарами
  /// без явного действия пользователя.
  Future<bool> handleLocationPermission({bool silent = false}) async {
    void message(String text) {
      if (!silent) _onMessage(text);
    }

    try {
      if (!await _dataSource.isServiceEnabled()) {
        message('Геолокация отключена');
        return false;
      }
      var permission = await _dataSource.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _dataSource.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        message('Нет разрешения на геолокацию');
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        message('Разрешение на геолокацию запрещено — включите в настройках');
        return false;
      }
      return true;
    } catch (_) {
      message('Геолокация недоступна');
      return false;
    }
  }

  Future<void> _locateAndMove({required bool follow}) async {
    final generation = _gestureGeneration;
    // Разрешение уже есть — слой маячка включаем сразу, не дожидаясь фикса:
    // позиции придут по стриму, а камера сдвинется ниже, когда фикс готов.
    if (!_locationLayerEnabled) {
      _locationLayerEnabled = true;
      _notify();
    }
    // Пользователь явно попросил геопозицию — поднимаем живой источник, чтобы
    // маячок не только появился, но и следовал за движением.
    _ensureLivePositionSource();
    Position? position;
    try {
      position = await _resolvePosition();
    } catch (_) {
      _onMessage('Включите геолокацию');
      return;
    }
    if (_disposed) return;
    if (position == null || !_isValidPosition(position)) {
      _onMessage('Не удалось определить местоположение');
      return;
    }
    // Досылаем фикс в общий поток, чтобы маячок отрисовался немедленно, даже
    // если непрерывный поток ещё не успел отдать первое событие.
    _lastPosition = position;
    final controller = _positionController;
    if (controller != null && !controller.isClosed) controller.add(position);
    if (generation != _gestureGeneration) {
      // Пока шёл фикс, пользователь сам сдвинул карту: камеру не перехватываем
      // и follow не навязываем.
      return;
    }
    _followLocation = follow;
    _notify();
    _moveCamera(
      LatLng(position.latitude, position.longitude),
      locationZoom,
    );
  }

  /// Последняя известная позиция — как быстрый путь и как фолбэк, если
  /// текущая недоступна (например, `getLastKnownPosition` не поддержан).
  Future<Position?> _resolvePosition() async {
    final lastKnown = await _dataSource.lastKnownPosition();
    if (lastKnown != null &&
        _isValidPosition(lastKnown) &&
        _isFresh(lastKnown)) {
      return lastKnown;
    }
    try {
      return await _dataSource.currentPosition();
    } catch (_) {
      return lastKnown;
    }
  }

  bool _isFresh(Position position) {
    if (lastKnownMaxAge <= Duration.zero) return true;
    final age = DateTime.now().difference(position.timestamp);
    return age <= lastKnownMaxAge;
  }

  bool _isValidPosition(Position position) =>
      position.latitude.isFinite &&
      position.longitude.isFinite &&
      position.latitude.abs() <= 90 &&
      position.longitude.abs() <= 180;

  void _moveCamera(LatLng center, double zoom, {double rotation = 0}) {
    _cameraEstablished = true;
    final sink = _moveSink;
    if (sink != null) {
      sink(center, zoom);
      return;
    }
    try {
      _mapController.move(center, zoom);
      if (rotation != 0) _mapController.rotate(rotation);
    } catch (_) {
      // Карта ещё не отрисована — перемещение применится позже.
    }
  }

  void flushCamera() {
    _persistDebounce?.cancel();
    _persistCamera();
  }

  void _persistCamera() {
    final snapshot = _pendingCamera;
    _pendingCamera = null;
    if (snapshot == null) return;
    unawaited(_cameraStore.save(snapshot));
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sourceLive = false;
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _positionController?.close();
    _positionController = null;
    final pending = _pendingCamera;
    _pendingCamera = null;
    if (pending != null) {
      // Досохраняем последнюю камеру, не блокируя dispose.
      unawaited(_cameraStore.save(pending));
    }
    super.dispose();
  }
}
