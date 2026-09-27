import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/presentation/widgets/poi/location_marker_stream.dart';
import 'package:digger_maps/presentation/providers/location_controller.dart';

/// Источник геолокации с управляемым потоком позиций: разрешение выдано,
/// поток отдаёт то, что мы в него положим (в отличие от пустого потока в
/// unit-тестах контроллера — здесь важно, что позиция реально доезжает до слоя).
class _FakeSource implements LocationDataSource {
  _FakeSource({this.lastKnown});

  Position? lastKnown;
  final StreamController<Position> live =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position?> lastKnownPosition() async => lastKnown;
  @override
  Future<Position> currentPosition() async => lastKnown ?? _pos(55.75, 37.61);
  @override
  Stream<Position> positionStream() => live.stream;
}

class _FakeStore implements MapCameraStore {
  @override
  Future<MapCameraSnapshot?> load() async => null;
  @override
  Future<void> save(MapCameraSnapshot snapshot) async {}
}

/// Диагностический тест реального пути отрисовки маячка:
/// broadcast-поток позиций (как `LocationController.positionStream`) →
/// `LocationMarkerStream` (мемоизация) → `CurrentLocationLayer` → маркер.
///
/// Проверяем именно то, что видит пользователь: появляется ли маркер и не
/// теряется ли он при пересборке карты / смене числа соседних слоёв.
Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late StreamController<Position> controller;
  Position? last;

  setUp(() {
    last = null;
    // Точная копия семантики LocationController: broadcast + повтор последней
    // позиции новому слушателю через onListen (иначе поздняя подписка после
    // пересборки слоя не получила бы уже случившийся фикс).
    controller = StreamController<Position>.broadcast(onListen: () {
      final l = last;
      if (l != null) controller.add(l);
    });
  });

  tearDown(() => controller.close());

  void emit(Position p) {
    last = p;
    controller.add(p);
  }

  // Тот же самый маркер, что в MapLayerStack, чтобы искать его по типу.
  Widget locationLayer() => LocationMarkerStream(
        stream: controller.stream,
        builder: (context, positions, headings) => CurrentLocationLayer(
          key: const ValueKey('current-location'),
          positionStream: positions,
          headingStream: headings,
          style: const LocationMarkerStyle(
            marker: DefaultLocationMarker(
              child: Icon(Icons.navigation, color: Colors.white, size: 18),
            ),
            markerSize: Size(28, 28),
          ),
        ),
      );

  // Реплика структуры children из MapLayerStack: переменное число слоёв ДО
  // маячка, а маячок и хвост (preview + attribution) — без ключей, как в бою.
  Widget mapWith({
    required bool locationEnabled,
    required int leadingLayers,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(55.75, 37.61),
            initialZoom: 15,
          ),
          children: <Widget>[
            const MarkerLayer(markers: <Marker>[]),
            for (var i = 0; i < leadingLayers; i++)
              const CircleLayer(circles: <CircleMarker>[]),
            if (locationEnabled) locationLayer(),
            // Хвост: как ObjectPreviewLayer + RichAttributionWidget — стабильные
            // типы после маячка (их сопоставляет нижний проход reconciliation).
            const MarkerLayer(markers: <Marker>[]),
            const RichAttributionWidget(
              attributions: <SourceAttribution>[
                TextSourceAttribution('© test'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Finder marker() => find.byType(DefaultLocationMarker);

  testWidgets('маркер появляется после первой позиции', (tester) async {
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 1));
    await tester.pump();
    expect(marker(), findsNothing, reason: 'до позиции маркера нет');

    emit(_pos(55.75, 37.61));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget, reason: 'после позиции маркер виден');
  });

  testWidgets('маркер переживает пересборку карты (тот же поток)',
      (tester) async {
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 1));
    emit(_pos(55.75, 37.61));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget);

    // Пересборка без изменения числа слоёв.
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget, reason: 'маркер не должен пропасть');
  });

  testWidgets('маркер переживает изменение числа предшествующих слоёв',
      (tester) async {
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 1));
    emit(_pos(55.75, 37.61));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget);

    // Включили ещё один слой ДО маячка (как wikimapia / импортированную карту):
    // индекс маячка в списке children сместился.
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(
      marker(),
      findsOneWidget,
      reason: 'смена числа соседних слоёв не должна гасить маячок',
    );
  });

  testWidgets('слой включён позже (false→true) — маркер появляется по replay',
      (tester) async {
    // Позиция пришла, пока слой был выключен (последняя известная сохранена).
    await tester.pumpWidget(mapWith(locationEnabled: false, leadingLayers: 1));
    emit(_pos(55.75, 37.61));
    await tester.pump();
    expect(marker(), findsNothing);

    // Пользователь включил слой — новый подписчик получает replay последней.
    await tester.pumpWidget(mapWith(locationEnabled: true, leadingLayers: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget, reason: 'replay последней позиции');
  });

  // Сквозной тест: реальный LocationController → его positionStream → реальный
  // CurrentLocationLayer. Доказывает, что после enableLocationLayer() позиция
  // из источника действительно доезжает до слоя и рисует маркер.
  testWidgets('LocationController.enableLocationLayer доводит позицию до слоя',
      (tester) async {
    final source = _FakeSource(lastKnown: _pos(55.75, 37.61));
    final loc = LocationController(
      mapController: MapController(),
      onMessage: (_) {},
      dataSource: source,
      cameraStore: _FakeStore(),
      moveSink: (_, __) {},
    );
    addTearDown(loc.dispose);

    await loc.enableLocationLayer();
    await tester.pump();
    expect(loc.locationLayerEnabled, isTrue,
        reason: 'слой включён после выдачи разрешения');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(55.75, 37.61),
              initialZoom: 15,
            ),
            children: <Widget>[
              const MarkerLayer(markers: <Marker>[]),
              if (loc.locationLayerEnabled)
                LocationMarkerStream(
                  stream: loc.positionStream,
                  builder: (context, positions, headings) =>
                      CurrentLocationLayer(
                    key: const ValueKey('current-location'),
                    positionStream: positions,
                    headingStream: headings,
                    style: const LocationMarkerStyle(
                      marker: DefaultLocationMarker(),
                      markerSize: Size(28, 28),
                    ),
                  ),
                ),
              const MarkerLayer(markers: <Marker>[]),
            ],
          ),
        ),
      ),
    );
    // Позиция из _pushFreshFix ещё в микротаске/onListen replay — прокачиваем.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget,
        reason: 'маркер виден: фикс из контроллера дошёл до слоя');

    // Движение обновляет маркер, а не гасит его.
    source.live.add(_pos(55.80, 37.70));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget, reason: 'маркер остаётся при обновлении');
  });

  testWidgets('битый heading (NaN) не прячет маркер', (tester) async {
    // Датчик ориентации на устройстве может отдать NaN/Infinity. При
    // markerDirection.heading пакет оборачивает маркер в Transform.rotate,
    // и нечисловой угол делает маркер невидимым, хотя позиция уже пришла и
    // камера отцентрирована. LocationMarkerStream очищает heading → маркер
    // остаётся виден, а поворот берётся числовой.
    final heading = StreamController<LocationMarkerHeading?>.broadcast();
    addTearDown(heading.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(55.75, 37.61),
              initialZoom: 15,
            ),
            children: <Widget>[
              const MarkerLayer(markers: <Marker>[]),
              LocationMarkerStream(
                stream: controller.stream,
                headingStream: heading.stream,
                builder: (context, positions, headings) => CurrentLocationLayer(
                  key: const ValueKey('current-location'),
                  positionStream: positions,
                  headingStream: headings,
                  style: const LocationMarkerStyle(
                    marker: DefaultLocationMarker(
                      child: Icon(Icons.navigation, color: Colors.white),
                    ),
                    markerSize: Size(28, 28),
                    markerDirection: MarkerDirection.heading,
                  ),
                ),
              ),
              const MarkerLayer(markers: <Marker>[]),
            ],
          ),
        ),
      ),
    );

    emit(_pos(55.75, 37.61));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(marker(), findsOneWidget, reason: 'маркер виден после позиции');

    // Пришло нечисловое направление.
    heading.add(
      const LocationMarkerHeading(heading: double.nan, accuracy: double.nan),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(marker(), findsOneWidget,
        reason: 'битый heading не должен убирать маркер');
    // Матрица поворота вокруг маркера остаётся числовой (без NaN),
    // иначе Skia не отрисовала бы маркер на устройстве.
    final transform = tester.widget<Transform>(
      find.ancestor(of: marker(), matching: find.byType(Transform)).first,
    );
    expect(
      transform.transform.storage.every((double v) => v.isFinite),
      isTrue,
      reason: 'Transform.rotate маркера не должен получить NaN-угол',
    );
  });
}
