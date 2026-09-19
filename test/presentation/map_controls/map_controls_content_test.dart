import 'package:digger_maps/presentation/providers/track_recording_controller.dart';
import 'package:digger_maps/presentation/widgets/map_controls/bottom_actions.dart';
import 'package:digger_maps/presentation/widgets/map_controls/calibration_controls.dart';
import 'package:digger_maps/presentation/widgets/map_controls/left_panel.dart';
import 'package:digger_maps/presentation/widgets/map_controls/recording_overlay.dart';
import 'package:digger_maps/presentation/widgets/map_controls/spectral_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpChild(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 800),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(body: Stack(children: <Widget>[child])),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Для содержимого с бесконечной анимацией (пульсация записи):
    // прокручиваем время дольше анимации панели (280 мс).
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Позиционирующие себя виджеты внутри [type] — у content-only их быть не должно.
Finder positionedInside(Type type) =>
    find.descendant(of: find.byType(type), matching: find.byType(Positioned));

Widget leftPanel({bool embedded = false}) => LeftPanel(
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

Widget spectralChip({bool embedded = false}) => SpectralStatusChip(
      date: DateTime(2024, 5, 12),
      cloudCoverage: 12,
      loading: false,
      onEdit: () {},
      onClose: () {},
      embedded: embedded,
    );

Widget bottomActions({
  required bool aiming,
  bool embedded = false,
  bool shiftEnabled = false,
  VoidCallback? onGpsPressed,
  VoidCallback? onGpsLongPress,
  VoidCallback? onShiftPressed,
  VoidCallback? onMapsPressed,
  VoidCallback? onAimCancel,
  VoidCallback? onAimDone,
}) =>
    BottomActions(
      following: false,
      recording: false,
      aiming: aiming,
      shiftEnabled: shiftEnabled,
      onGpsPressed: onGpsPressed ?? () {},
      onGpsLongPress: onGpsLongPress ?? () {},
      onShiftPressed: onShiftPressed ?? () {},
      onMapsPressed: onMapsPressed ?? () {},
      onAimCancel: onAimCancel ?? () {},
      onAimDone: onAimDone ?? () {},
      embedded: embedded,
    );

void main() {
  group('content-only (embedded) — без собственного Positioned', () {
    testWidgets('SpectralStatusChip', (tester) async {
      await pumpChild(tester, spectralChip(embedded: true));
      expect(positionedInside(SpectralStatusChip), findsNothing);
      expect(find.text('12.05 • Обл. 12%'), findsOneWidget);

      await pumpChild(tester, spectralChip());
      final positioned =
          tester.widget<Positioned>(positionedInside(SpectralStatusChip));
      expect(positioned.left, 16);
      expect(positioned.right, 88);
      expect(positioned.bottom, 16);
    });

    testWidgets('LeftPanel', (tester) async {
      await pumpChild(tester, leftPanel(embedded: true));
      expect(positionedInside(LeftPanel), findsNothing);
      expect(find.text('W'), findsOneWidget);

      await pumpChild(tester, leftPanel());
      final positioned = tester.widget<Positioned>(positionedInside(LeftPanel));
      expect(positioned.left, 12);
      expect(positioned.top, closeTo(800 * 0.25, 0.1));
    });

    testWidgets('BottomActions: рейл и прицеливание', (tester) async {
      await pumpChild(tester, bottomActions(aiming: false, embedded: true));
      expect(positionedInside(BottomActions), findsNothing);
      expect(find.text('GPS'), findsOneWidget);
      expect(find.text('Сдвиг'), findsOneWidget);
      expect(find.text('Карты'), findsOneWidget);

      await pumpChild(tester, bottomActions(aiming: true, embedded: true));
      expect(positionedInside(BottomActions), findsNothing);
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);

      // Legacy-режим сохраняет прежние отступы.
      await pumpChild(tester, bottomActions(aiming: false));
      final rail = tester.widget<Positioned>(positionedInside(BottomActions));
      expect(rail.right, 16);
      expect(rail.bottom, 16);
      expect(rail.left, isNull);

      await pumpChild(tester, bottomActions(aiming: true));
      final aim = tester.widget<Positioned>(positionedInside(BottomActions));
      expect(aim.left, 16);
      expect(aim.right, 16);
      expect(aim.bottom, 16);
    });
  });

  group('BottomActions: действия', () {
    testWidgets('GPS, «Сдвиг» и «Карты»', (tester) async {
      var gps = 0;
      var gpsLong = 0;
      var shift = 0;
      var maps = 0;
      await pumpChild(
        tester,
        bottomActions(
          aiming: false,
          embedded: true,
          onGpsPressed: () => gps++,
          onGpsLongPress: () => gpsLong++,
          onShiftPressed: () => shift++,
          onMapsPressed: () => maps++,
        ),
      );

      await tester.tap(find.byIcon(Icons.my_location_rounded));
      expect(gps, 1);
      await tester.longPress(find.byIcon(Icons.my_location_rounded));
      expect(gpsLong, 1);
      await tester.tap(find.byIcon(Icons.map_outlined));
      expect(maps, 1);
      // «Сдвиг» недоступен, пока не выбрана растровая карта.
      await tester.tap(find.byIcon(Icons.open_with));
      expect(shift, 0);

      await pumpChild(
        tester,
        bottomActions(
          aiming: false,
          embedded: true,
          shiftEnabled: true,
          onShiftPressed: () => shift++,
        ),
      );
      await tester.tap(find.byIcon(Icons.open_with));
      expect(shift, 1);
    });

    testWidgets('кнопки прицеливания', (tester) async {
      var cancel = 0;
      var done = 0;
      await pumpChild(
        tester,
        bottomActions(
          aiming: true,
          embedded: true,
          onAimCancel: () => cancel++,
          onAimDone: () => done++,
        ),
      );
      await tester.tap(find.text('Отмена'));
      expect(cancel, 1);
      await tester.tap(find.text('Готово'));
      expect(done, 1);
    });
  });

  testWidgets('CalibrationPanel: слайдер, DPad, сброс и «Готово»',
      (tester) async {
    final steps = <int>[];
    final shifts = <String>[];
    var resets = 0;
    var dones = 0;
    await pumpChild(
      tester,
      CalibrationPanel(
        mapName: 'Спутник 2024',
        stepMeters: 10,
        onStepChanged: steps.add,
        onShift: (x, y) => shifts.add('$x:$y'),
        onReset: () => resets++,
        onDone: () => dones++,
      ),
    );

    expect(find.text('Сдвиг: Спутник 2024'), findsOneWidget);
    expect(find.text('10 м'), findsOneWidget);

    await tester
        .tapAt(tester.getCenter(find.byType(Slider)) + const Offset(20, 0));
    expect(steps, isNotEmpty);

    await tester.tap(find.byIcon(Icons.north_west));
    expect(shifts, ['-1:1']);
    await tester.tap(find.byIcon(Icons.adjust));
    expect(resets, 1);
    await tester.tap(find.text('Готово'));
    expect(dones, 1);
  });

  group('RecordingOverlay: разделение на stats/controls', () {
    Widget stats({required bool recording, bool paused = false}) =>
        RecordingStatsCard(
          isRecording: recording,
          isPaused: paused,
          speedKmh: 12.34,
          distanceKm: 1.5,
        );

    Widget controls({required bool recording, bool paused = false}) =>
        RecordingControlsPanel(
          isRecording: recording,
          isPaused: paused,
          onStop: () {},
          onTogglePause: () {},
          onCancel: () {},
        );

    testWidgets('карточка статистики появляется и исчезает', (tester) async {
      await pumpChild(tester, stats(recording: false));
      expect(find.text('Идёт запись трека'), findsNothing);

      // Во время записи индикатор пульсирует бесконечно — settle: false.
      await pumpChild(tester, stats(recording: true), settle: false);
      expect(find.text('Идёт запись трека'), findsOneWidget);
      expect(find.text('12.3 км/ч'), findsOneWidget);
      expect(find.text('1.50 км'), findsOneWidget);

      await pumpChild(
        tester,
        stats(recording: true, paused: true),
        settle: false,
      );
      expect(find.text('Запись приостановлена'), findsOneWidget);

      await pumpChild(tester, stats(recording: false));
      expect(find.text('Идёт запись трека'), findsNothing);
    });

    testWidgets('контролы записи и их колбэки', (tester) async {
      var stops = 0;
      var pauses = 0;
      var cancels = 0;

      await pumpChild(tester, controls(recording: false));
      expect(find.text('Стоп'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingControlsPanel(
              isRecording: true,
              isPaused: false,
              onStop: () => stops++,
              onTogglePause: () => pauses++,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Стоп'), findsOneWidget);
      expect(find.text('Пауза'), findsOneWidget);
      await tester.tap(find.text('Стоп'));
      await tester.tap(find.text('Пауза'));
      await tester.tap(find.text('Отмена'));
      expect(stops, 1);
      expect(pauses, 1);
      expect(cancels, 1);

      await pumpChild(tester, controls(recording: true, paused: true));
      expect(find.text('Продолжить'), findsOneWidget);

      await pumpChild(tester, controls(recording: false));
      expect(find.text('Стоп'), findsNothing);
    });

    testWidgets('legacy RecordingOverlay сохраняет прежние отступы',
        (tester) async {
      final controller = TrackRecordingController(
        ensureLocationPermission: () async => false,
      );
      addTearDown(controller.dispose);

      await pumpChild(
        tester,
        RecordingOverlay(
          controller: controller,
          onStop: () {},
          onCancel: () {},
          spectralVisible: false,
        ),
      );
      final plain = tester
          .widgetList<Positioned>(positionedInside(RecordingOverlay))
          .toList();
      expect(plain.any((p) => p.top == 150 && p.right == 16), isTrue);
      expect(
        plain.any((p) => p.left == 16 && p.right == 88 && p.bottom == 16),
        isTrue,
      );

      await pumpChild(
        tester,
        RecordingOverlay(
          controller: controller,
          onStop: () {},
          onCancel: () {},
          spectralVisible: true,
        ),
      );
      final withSpectral = tester
          .widgetList<Positioned>(positionedInside(RecordingOverlay))
          .toList();
      expect(withSpectral.any((p) => p.bottom == 72), isTrue);
    });

    testWidgets('адаптеры контроллера рендерятся без активной записи',
        (tester) async {
      final controller = TrackRecordingController(
        ensureLocationPermission: () async => false,
      );
      addTearDown(controller.dispose);

      await pumpChild(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TrackRecordingStatsCard(controller: controller),
            TrackRecordingControlsPanel(
              controller: controller,
              onStop: () {},
              onCancel: () {},
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Стоп'), findsNothing);
      expect(find.text('Идёт запись трека'), findsNothing);
    });
  });
}
