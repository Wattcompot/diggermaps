import 'dart:async';

import 'package:digger_maps/presentation/providers/location_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class _FakeLocationDataSource implements LocationDataSource {
  _FakeLocationDataSource({
    this.current,
    this.lastKnown,
    this.permission = LocationPermission.whileInUse,
    this.currentCompleter,
    this.currentError,
  });

  Position? current;
  Position? lastKnown;
  LocationPermission permission;
  bool serviceEnabled = true;
  Completer<Position>? currentCompleter;
  Object? currentError;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;

  @override
  Future<Position> currentPosition() async {
    final completer = currentCompleter;
    if (completer != null) return completer.future;
    final error = currentError;
    if (error != null) throw error;
    return current ?? _position(0, 0);
  }

  @override
  Stream<Position> positionStream() => const Stream<Position>.empty();
}

class _FakeCameraStore implements MapCameraStore {
  _FakeCameraStore([this.stored]);

  MapCameraSnapshot? stored;
  int saveCount = 0;
  MapCameraSnapshot? lastSaved;

  @override
  Future<MapCameraSnapshot?> load() async => stored;

  @override
  Future<void> save(MapCameraSnapshot snapshot) async {
    saveCount++;
    lastSaved = snapshot;
  }
}

Position _position(double latitude, double longitude, {DateTime? timestamp}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

MapCamera _camera(double latitude, double longitude, double zoom) {
  return MapCamera(
    crs: const Epsg3857(),
    center: LatLng(latitude, longitude),
    zoom: zoom,
    rotation: 0,
    nonRotatedSize: const Size(400, 600),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('карта готова раньше префов: GPS всё равно запрашивается', () async {
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: _FakeLocationDataSource(current: _position(48, 2)),
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );
    controller.restoreCameraOnReady();
    await pumpEventQueue();
    expect(moves, [const LatLng(48, 2)]);
    controller.dispose();
  });

  test('нейтральная камера не сохраняется без GPS или жеста', () async {
    final store = _FakeCameraStore();
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: _FakeLocationDataSource(),
      cameraStore: store,
      persistenceDebounce: Duration.zero,
    );
    controller.onCameraChanged(_camera(0, 0, 2), hasGesture: false);
    await pumpEventQueue();
    expect(store.saveCount, 0);
    controller.dispose();
  });

  test('невалидный GPS не перемещает камеру', () async {
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: _FakeLocationDataSource(current: _position(double.nan, 2)),
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );
    await controller.centerOnceOnLocation();
    expect(moves, isEmpty);
    controller.dispose();
  });

  test('при старте приоритет у сохранённой камеры: GPS её не перебивает',
      () async {
    final dataSource = _FakeLocationDataSource(
      current: _position(55.7512, 37.6184),
      lastKnown: _position(55.7512, 37.6184),
    );
    final store = _FakeCameraStore(
      const MapCameraSnapshot(latitude: 48.8566, longitude: 2.3522, zoom: 11),
    );
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: store,
      moveSink: (center, zoom) => moves.add(center),
    );

    await pumpEventQueue();
    controller.restoreCameraOnReady();
    await pumpEventQueue();

    expect(moves, hasLength(1));
    expect(moves.single.latitude, closeTo(48.8566, 1e-6));
    expect(moves.single.longitude, closeTo(2.3522, 1e-6));
    controller.dispose();
  });

  test('без сохранённой камеры старт центрируется по геопозиции', () async {
    final dataSource = _FakeLocationDataSource(
      current: _position(55.7512, 37.6184),
      lastKnown: _position(55.7512, 37.6184),
    );
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );

    await pumpEventQueue();
    controller.restoreCameraOnReady();
    await pumpEventQueue();

    expect(moves, hasLength(1));
    expect(moves.single.latitude, closeTo(55.7512, 1e-6));
    controller.dispose();
  });

  test('битая сохранённая камера игнорируется', () async {
    expect(
      const MapCameraSnapshot(latitude: 999, longitude: 0, zoom: 5).isValid,
      isFalse,
    );
    expect(
      const MapCameraSnapshot(latitude: 55, longitude: 37, zoom: 99).isValid,
      isFalse,
    );
    expect(
      const MapCameraSnapshot(latitude: 55, longitude: 37, zoom: 12).isValid,
      isTrue,
    );

    final dataSource = _FakeLocationDataSource(
      current: _position(55.7512, 37.6184),
      lastKnown: _position(55.7512, 37.6184),
    );
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: _FakeCameraStore(
        const MapCameraSnapshot(latitude: 999, longitude: 0, zoom: 5),
      ),
      moveSink: (center, zoom) => moves.add(center),
    );

    await pumpEventQueue();
    controller.restoreCameraOnReady();
    await pumpEventQueue();

    expect(moves.single.latitude, closeTo(55.7512, 1e-6));
    controller.dispose();
  });

  test('жест пользователя во время GPS-фикса не перехватывает камеру',
      () async {
    final completer = Completer<Position>();
    final dataSource = _FakeLocationDataSource(currentCompleter: completer);
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );

    final pending = controller.centerOnceOnLocation();
    await pumpEventQueue();
    controller.onUserGesture();
    completer.complete(_position(55.7512, 37.6184));
    await pending;

    expect(moves, isEmpty);
    expect(controller.locationLayerEnabled, isTrue);
    controller.dispose();
  });

  test('несвежая last-known не используется: запрашивается текущая позиция',
      () async {
    final dataSource = _FakeLocationDataSource(
      lastKnown: _position(
        10,
        20,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      current: _position(55.7512, 37.6184),
    );
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );

    await pumpEventQueue();
    controller.restoreCameraOnReady();
    await pumpEventQueue();

    expect(moves.single.latitude, closeTo(55.7512, 1e-6));
    controller.dispose();
  });

  test('последняя известная используется как фолбэк, если текущая недоступна',
      () async {
    final dataSource = _FakeLocationDataSource(
      lastKnown: _position(55.7512, 37.6184),
      currentError: Exception('timeout'),
    );
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: dataSource,
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );

    await pumpEventQueue();
    controller.restoreCameraOnReady();
    await pumpEventQueue();

    expect(moves.single.latitude, closeTo(55.7512, 1e-6));
    controller.dispose();
  });

  test('перемещение карты сохраняется с дебаунсом', () async {
    final store = _FakeCameraStore();
    final controller = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: _FakeLocationDataSource(),
      cameraStore: store,
      persistenceDebounce: const Duration(milliseconds: 30),
      moveSink: (center, zoom) {},
    );
    final camera = _camera(55.7512, 37.6184, 12);

    controller.onCameraChanged(camera, hasGesture: true);
    controller.onCameraChanged(camera, hasGesture: true);
    controller.onCameraChanged(camera, hasGesture: true);
    expect(store.saveCount, 0, reason: 'на каждый кадр на диск не пишем');

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(store.saveCount, 1);
    expect(store.lastSaved!.zoom, 12);
    expect(store.lastSaved!.latitude, closeTo(55.7512, 1e-6));

    controller.dispose();
  });

  test('разрешение deniedForever даёт сообщение и не двигает камеру', () async {
    final messages = <String>[];
    final moves = <LatLng>[];
    final controller = LocationController(
      mapController: MapController(),
      onMessage: messages.add,
      dataSource: _FakeLocationDataSource(
        permission: LocationPermission.deniedForever,
        current: _position(55.7512, 37.6184),
      ),
      cameraStore: _FakeCameraStore(),
      moveSink: (center, zoom) => moves.add(center),
    );

    await controller.centerOnceOnLocation();

    expect(moves, isEmpty);
    expect(messages, isNotEmpty);
    controller.dispose();
  });
}
