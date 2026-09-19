import 'package:digger_maps/presentation/widgets/map_controls/bottom_actions.dart';
import 'package:digger_maps/presentation/widgets/map_controls/calibration_controls.dart';
import 'package:digger_maps/presentation/widgets/map_controls/left_panel.dart';
import 'package:digger_maps/presentation/widgets/map_controls/map_bottom_dock.dart';
import 'package:digger_maps/presentation/widgets/map_controls/recording_overlay.dart';
import 'package:digger_maps/presentation/widgets/map_controls/spectral_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обёртка: док возвращает `Positioned.fill`, поэтому живёт в `Stack`.
///
/// [settle] = false — для содержимого с бесконечной анимацией (пульсация
/// индикатора записи), где `pumpAndSettle` никогда не завершится.
Future<void> pumpDock(
  WidgetTester tester, {
  required Size size,
  required Widget dock,
  double textScale = 1,
  List<Widget> underlay = const <Widget>[],
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Stack(children: <Widget>[...underlay, dock]),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Блок панели: растягивается по ширине стопки (как реальные панели).
Widget stackedBlock(String key, double height) =>
    Container(key: Key(key), height: height, color: Colors.transparent);

/// Блок рейла: собственная ширина.
Widget railBlock(String key, {required double width, required double height}) =>
    Container(
      key: Key(key),
      width: width,
      height: height,
      color: Colors.transparent,
    );

Widget leftPanel({bool embedded = true}) => LeftPanel(
      mapController: MapController(),
      rotation: 0,
      spectralActive: false,
      onWikimapiaPressed: () {},
      onBrushPressed: () {},
      onSpectralPressed: () {},
      onSpectralLongPress: () {},
      onCenterPressed: () {},
      onCompassPressed: () {},
      embedded: embedded,
    );

Widget spectralChip({bool embedded = true}) => SpectralStatusChip(
      date: DateTime(2024, 5, 12),
      cloudCoverage: 12,
      loading: false,
      onEdit: () {},
      onClose: () {},
      embedded: embedded,
    );

Widget calibrationPanel() => CalibrationPanel(
      mapName: 'Спутник 2024',
      stepMeters: 10,
      onStepChanged: (_) {},
      onShift: (x, y) {},
      onReset: () {},
      onDone: () {},
    );

Widget actionRail() => ActionRail(
      following: false,
      recording: false,
      shiftEnabled: true,
      onGpsPressed: () {},
      onGpsLongPress: () {},
      onShiftPressed: () {},
      onMapsPressed: () {},
    );

/// Находит прокручиваемую область дока, содержащую [inside].
ScrollableState dockScrollWith(WidgetTester tester, Finder inside) {
  final scrollables = find.descendant(
    of: find.byType(MapBottomDock),
    matching: find.byType(Scrollable),
  );
  for (final element in scrollables.evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    final inThis = find
        .descendant(of: find.byWidget(state.widget), matching: inside)
        .evaluate()
        .isNotEmpty;
    if (inThis) return state;
  }
  fail('Не найдена прокручиваемая область с $inside');
}

void main() {
  testWidgets('портрет: стопка и рейл снизу, без наложений', (tester) async {
    await pumpDock(
      tester,
      size: const Size(400, 800),
      dock: MapBottomDock(
        leftPanel: railBlock('rail', width: 44, height: 200),
        stats: railBlock('stats', width: 206, height: 90),
        primaryPanel: stackedBlock('primary', 40),
        panels: <Widget>[
          stackedBlock('p1', 64),
          stackedBlock('p2', 56),
        ],
        trailing: railBlock('trail', width: 48, height: 209),
      ),
    );

    expect(tester.takeException(), isNull);

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final p1 = tester.getRect(find.byKey(const Key('p1')));
    final p2 = tester.getRect(find.byKey(const Key('p2')));
    final rail = tester.getRect(find.byKey(const Key('rail')));
    final stats = tester.getRect(find.byKey(const Key('stats')));
    final trail = tester.getRect(find.byKey(const Key('trail')));

    // Низ стопки и низ экшен-рейла совпадают (прежде у обоих было bottom: 16).
    expect(p2.bottom, closeTo(784, 0.1));
    expect(trail.bottom, closeTo(784, 0.1));
    // Рейл справа: 16 (padding) + 24 (зазор) + 48 = 88 — как прежний right: 88.
    expect(trail.left, closeTo(336, 0.1));
    expect(p2.right, closeTo(312, 0.1));
    // Панели стоят друг над другом по фактическим высотам.
    expect(p1.bottom + 8, closeTo(p2.top, 0.1));
    expect(primary.bottom + 8, closeTo(p1.top, 0.1));
    // Левый рейл — на 25% высоты экрана, карточка записи — как раньше.
    expect(rail.top, closeTo(200, 0.1));
    expect(stats.top, closeTo(150, 0.1));
    expect(stats.right, closeTo(384, 0.1));
    // Ничего не пересекается.
    expect(rail.bottom, lessThanOrEqualTo(primary.top));
    expect(stats.bottom, lessThanOrEqualTo(primary.top));
    expect(trail.left, greaterThan(p2.right));
  });

  testWidgets('прицеливание: стопка не поднимается к прицелу', (tester) async {
    const size = Size(400, 600);
    Widget dock({required bool aiming}) => MapBottomDock(
          aiming: aiming,
          primaryPanel: stackedBlock('primary', 400),
        );

    await pumpDock(
      tester,
      size: size,
      dock: dock(aiming: true),
      underlay: <Widget>[
        const Positioned.fill(
          child: Center(
            child: SizedBox(
              key: Key('reticle'),
              width: 44,
              height: 44,
            ),
          ),
        ),
      ],
    );

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final reticle = tester.getRect(find.byKey(const Key('reticle')));
    // Центр экрана — 300, прицел занимает 278..322.
    expect(reticle.center.dy, closeTo(size.height / 2, 0.1));
    // Стопка строго ниже центра и ниже самого прицела.
    expect(primary.top, greaterThanOrEqualTo(size.height / 2 + 28));
    expect(primary.top, closeTo(328, 0.1));
    expect(reticle.bottom, lessThanOrEqualTo(primary.top));

    // Без прицеливания тот же контент может подниматься выше центра.
    await pumpDock(tester, size: size, dock: dock(aiming: false));
    final plain = tester.getRect(find.byKey(const Key('primary')));
    expect(plain.top, lessThan(size.height / 2));
  });

  testWidgets('низкий экран: стопка и рейл прокручиваются, а не переполняются',
      (tester) async {
    const size = Size(800, 360);
    await pumpDock(
      tester,
      size: size,
      dock: MapBottomDock(
        leftPanel: leftPanel(),
        primaryPanel: calibrationPanel(),
        panels: <Widget>[spectralChip()],
        trailing: actionRail(),
      ),
    );

    expect(tester.takeException(), isNull);

    // Стопка выше лимита (0.62 * 360 - 16 - 28) — значит она прокручивается.
    final stackScroll = dockScrollWith(tester, find.text('Готово'));
    expect(stackScroll.position.maxScrollExtent, greaterThan(0));

    // Левый рейл не влезает в остаток экрана — тоже прокручивается.
    final railScroll = dockScrollWith(tester, find.text('W'));
    expect(railScroll.position.maxScrollExtent, greaterThan(0));

    // Прокрутив стопку вниз, до «Готово» реально можно добраться.
    stackScroll.position.jumpTo(stackScroll.position.maxScrollExtent);
    await tester.pump();
    final done = tester.getRect(find.text('Готово'));
    expect(done.bottom, lessThanOrEqualTo(size.height));
    expect(done.top, greaterThan(0));
  });

  testWidgets('узкий экран и крупный текст: без переполнений', (tester) async {
    await pumpDock(
      tester,
      size: const Size(320, 480),
      textScale: 2,
      // Карточка записи пульсирует бесконечно — settle не дождаться.
      settle: false,
      dock: MapBottomDock(
        aiming: true,
        leftPanel: leftPanel(),
        stats: const RecordingStatsCard(
          isRecording: true,
          isPaused: false,
          speedKmh: 42.5,
          distanceKm: 3.25,
        ),
        primaryPanel: AimActions(onCancel: () {}, onDone: () {}),
        panels: <Widget>[
          RecordingControlsPanel(
            isRecording: true,
            isPaused: false,
            onStop: () {},
            onTogglePause: () {},
            onCancel: () {},
          ),
          spectralChip(),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Идёт запись трека'), findsOneWidget);
    expect(find.text('42.5 км/ч'), findsOneWidget);
    // «Отмена» есть и у прицеливания, и у контролов записи.
    expect(find.text('Отмена'), findsNWidgets(2));
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Стоп'), findsOneWidget);
  });

  testWidgets('комбинация: прицеливание + запись + снимки', (tester) async {
    const size = Size(400, 700);
    await pumpDock(
      tester,
      size: size,
      dock: MapBottomDock(
        aiming: true,
        stats: railBlock('stats', width: 206, height: 90),
        primaryPanel: stackedBlock('primary', 48),
        panels: <Widget>[
          stackedBlock('p1', 64),
          stackedBlock('p2', 48),
        ],
      ),
      underlay: <Widget>[
        const Positioned.fill(
          child: Center(
            child: SizedBox(
              key: Key('reticle'),
              width: 44,
              height: 44,
            ),
          ),
        ),
      ],
    );

    expect(tester.takeException(), isNull);

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final p1 = tester.getRect(find.byKey(const Key('p1')));
    final p2 = tester.getRect(find.byKey(const Key('p2')));
    final stats = tester.getRect(find.byKey(const Key('stats')));
    final reticle = tester.getRect(find.byKey(const Key('reticle')));

    expect(p2.bottom, closeTo(size.height - 16, 0.1));
    expect(p1.bottom + 8, closeTo(p2.top, 0.1));
    expect(primary.bottom + 8, closeTo(p1.top, 0.1));
    // Порядок стопки: прицел сверху, ниже контролы записи, ниже снимки.
    expect(primary.top, greaterThan(reticle.bottom));
    // Карточка записи не пересекается со стопкой.
    expect(stats.bottom, lessThanOrEqualTo(primary.top));
  });

  testWidgets('пустые участки не перехватывают нажатия карты', (tester) async {
    var taps = 0;
    await pumpDock(
      tester,
      size: const Size(400, 800),
      underlay: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            key: const Key('map'),
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ],
      dock: MapBottomDock(
        leftPanel: railBlock('rail', width: 44, height: 200),
        stats: railBlock('stats', width: 206, height: 90),
        primaryPanel: stackedBlock('primary', 40),
        panels: <Widget>[
          stackedBlock('p1', 64),
          stackedBlock('p2', 56),
        ],
        trailing: railBlock('trail', width: 48, height: 209),
      ),
    );

    // Между левым рейлом и карточкой записи.
    await tester.tapAt(const Offset(120, 300));
    expect(taps, 1);
    // Между карточкой и нижней стопкой.
    await tester.tapAt(const Offset(200, 450));
    expect(taps, 2);
    // По блоку панели — нажатие забирает сама панель.
    await tester.tapAt(const Offset(200, 740));
    expect(taps, 2);
  });

  testWidgets('пустой док ничего не рисует и не ломает раскладку',
      (tester) async {
    await pumpDock(
      tester,
      size: const Size(400, 800),
      dock: const MapBottomDock(),
    );
    expect(tester.takeException(), isNull);
  });
}
