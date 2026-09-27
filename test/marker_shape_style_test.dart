import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/presentation/widgets/bottom_sheets/marker_style_picker_sheet.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_appearance_button.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_builder.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_shape.dart';

void main() {
  group('палитра меток', () {
    test('ровно один коричневый, красный совпадает с дефолтом', () {
      const colors = MarkerStylePickerSheet.colors;

      // Раньше в пикере рядом жили два почти одинаковых коричневых.
      expect(colors.containsKey('#C4956A'), isTrue);
      expect(colors.containsKey('#A67B5B'), isFalse,
          reason: 'Лишний коричневый удалён из источника');

      // Красный по умолчанию у новой метки, а не отдельный Material-оттенок.
      expect(colors.containsKey('#FF0000'), isTrue);
      expect(colors.containsKey('#F44336'), isFalse);

      // Нет дублей ни по значению, ни по подписи.
      expect(colors.keys.toSet().length, colors.length);
      expect(colors.values.toSet().length, colors.length);
      for (final key in colors.keys) {
        expect(RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(key), isTrue,
            reason: 'Некорректный hex: $key');
      }
    });

    test('удалённый из палитры цвет остаётся валидным для старых меток', () {
      // Сохранённые метки со старым коричневым продолжают рисоваться: рендер
      // не зависит от того, есть ли цвет в палитре пикера.
      const legacy = Color(0xFFA67B5B);
      expect(MarkerBuilder.parseColorHex('#A67B5B'), legacy);
      const painter = MarkerShapePainter(shape: 'pin', color: legacy);
      expect(
        painter.buildPath(const Size(24, 24)).computeMetrics().isNotEmpty,
        isTrue,
      );
    });
  });

  group('MarkerShape', () {
    test('все формы строят непустой силуэт в границах холста', () {
      for (final shape in MarkerStylePickerSheet.shapes.keys) {
        final painter = MarkerShapePainter(
          shape: shape,
          color: const Color(0xFFFF0000),
        );
        final path = painter.buildPath(const Size(32, 32));
        expect(path.computeMetrics().isNotEmpty, isTrue, reason: shape);
        final bounds = path.getBounds();
        expect(bounds.left, greaterThanOrEqualTo(0), reason: shape);
        expect(bounds.top, greaterThanOrEqualTo(0), reason: shape);
        expect(bounds.right, lessThanOrEqualTo(32.0001), reason: shape);
        expect(bounds.bottom, lessThanOrEqualTo(32.0001), reason: shape);
      }
    });

    test('исторические значения формы нормализуются в булавку', () {
      expect(MarkerShapePainter.normalize('pin'), 'pin');
      expect(MarkerShapePainter.normalize('place'), 'pin');
      expect(MarkerShapePainter.normalize('location_on'), 'pin');
      expect(MarkerShapePainter.normalize('совсем-не-форма'), 'pin');
    });

    testWidgets('MarkerShape рисуется общим painter', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MarkerShape(
              shape: 'work',
              color: Color(0xFFFF0000),
              size: 40,
            ),
          ),
        ),
      ));

      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(MarkerShape),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(paint.painter, isA<MarkerShapePainter>());
      final painter = paint.painter! as MarkerShapePainter;
      expect(painter.shape, 'work');
      expect(painter.color, const Color(0xFFFF0000));
    });
  });

  group('живой размер', () {
    testWidgets('пикер анимирует предпросмотр к выбранному размеру',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MarkerStylePickerSheet(
            point: LatLng(0, 0),
            initialShape: 'pin',
            initialColor: '#C4956A',
            initialSize: 24,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
          tester.widget<MarkerShape>(find.byType(MarkerShape).first).size, 24);

      await tester.tap(find.text('Большой'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid =
          tester.widget<MarkerShape>(find.byType(MarkerShape).first).size;
      expect(mid, greaterThan(24));
      expect(mid, lessThan(48),
          reason: 'Размер должен меняться анимацией, а не скачком');

      await tester.pumpAndSettle();
      expect(
          tester.widget<MarkerShape>(find.byType(MarkerShape).first).size, 48);
    });

    testWidgets('кнопка внешнего вида анимирует размер метки', (tester) async {
      Widget build(double size) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: MarkerAppearanceButton(
                  shape: 'pin',
                  colorHex: '#FF0000',
                  size: size,
                  onTap: () {},
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(24));
      await tester.pumpAndSettle();
      expect(tester.widget<MarkerShape>(find.byType(MarkerShape)).size, 24);

      await tester.pumpWidget(build(48));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.widget<MarkerShape>(find.byType(MarkerShape)).size;
      expect(mid, greaterThan(24));
      expect(mid, lessThan(48));

      await tester.pumpAndSettle();
      expect(tester.widget<MarkerShape>(find.byType(MarkerShape)).size, 48);
    });
  });

  group('размеры метки', () {
    test('предустановки — источник правды, дефолт внутри них', () {
      final sizes = MarkerStylePickerSheet.sizes;

      expect(sizes.keys.toList(), <double>[24, 32, 48]);
      expect(sizes.values.toSet().length, sizes.length,
          reason: 'Подписи размеров не должны дублироваться');
      expect(sizes.containsKey(MarkerStylePickerSheet.defaultSize), isTrue,
          reason: 'Дефолт обязан быть выбираемым чипом, а не «Сохранённым»');
      expect(sizes.containsKey(42), isFalse);
    });

    test('все формы строят силуэт в границах холста на 24/32/48', () {
      for (final size in MarkerStylePickerSheet.sizes.keys) {
        for (final shape in MarkerStylePickerSheet.shapes.keys) {
          final painter = MarkerShapePainter(
            shape: shape,
            color: const Color(0xFFFF0000),
          );
          final path = painter.buildPath(Size(size, size));
          final reason = '$shape@$size';
          expect(path.computeMetrics().isNotEmpty, isTrue, reason: reason);
          final bounds = path.getBounds();
          expect(bounds.left, greaterThanOrEqualTo(0), reason: reason);
          expect(bounds.top, greaterThanOrEqualTo(0), reason: reason);
          expect(bounds.right, lessThanOrEqualTo(size + 0.0001),
              reason: reason);
          expect(bounds.bottom, lessThanOrEqualTo(size + 0.0001),
              reason: reason);
        }
      }
    });

    testWidgets('все формы рисуются общим painter на 24/32/48', (tester) async {
      for (final size in MarkerStylePickerSheet.sizes.keys) {
        for (final shape in MarkerStylePickerSheet.shapes.keys) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Center(
                child: MarkerShape(
                  shape: shape,
                  color: const Color(0xFFFF0000),
                  size: size,
                ),
              ),
            ),
          ));

          final reason = '$shape@$size';
          final paint = tester.widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(MarkerShape),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );
          expect(paint.painter, isA<MarkerShapePainter>(), reason: reason);
          final painter = paint.painter! as MarkerShapePainter;
          expect(painter.shape, shape, reason: reason);
          expect(
            painter.buildPath(Size(size, size)).computeMetrics().isNotEmpty,
            isTrue,
            reason: reason,
          );
        }
      }
    });

    testWidgets('legacy-размер 42 не подменяется на 48 и возвращается как есть',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      MarkerStyleSelection? result;
      await tester.pumpWidget(
          _sheetLauncher(initialSize: 42, onResult: (value) => result = value));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.length, MarkerStylePickerSheet.sizes.length);
      expect(chips.every((chip) => !chip.selected), isTrue,
          reason: '42 — не предустановка, ни один чип не должен быть выбран');

      // Пояснение вместо второго контрола: это обычный текст, а не чип.
      expect(find.text('Сохранённый размер: 42'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Сохранённый размер: 42'),
          findsNothing);

      // Пока пользователь не выбрал предустановку, рисуется фактический размер.
      expect(
          tester.widget<MarkerShape>(find.byType(MarkerShape).first).size, 42);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.size, 42,
          reason: 'Сохранённый размер возвращается без подмены на 48');
      expect(result!.shape, 'pin');
      expect(result!.colorHex, '#C4956A');
    });

    testWidgets('предустановка рисует и возвращает именно выбранный размер',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final entry in MarkerStylePickerSheet.sizes.entries) {
        MarkerStyleSelection? result;
        await tester.pumpWidget(_sheetLauncher(
            initialSize: MarkerStylePickerSheet.defaultSize,
            onResult: (value) => result = value));
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();

        await tester.tap(find.text(entry.value));
        await tester.pumpAndSettle();

        final reason = '${entry.value} (${entry.key})';
        expect(
            tester
                .widget<ChoiceChip>(
                    find.widgetWithText(ChoiceChip, entry.value))
                .selected,
            isTrue,
            reason: reason);
        expect(tester.widget<MarkerShape>(find.byType(MarkerShape).first).size,
            entry.key,
            reason: 'Предпросмотр рисует фактический размер $reason');
        expect(find.textContaining('Сохранённый размер'), findsNothing,
            reason: reason);

        await tester.tap(find.text('Готово'));
        await tester.pumpAndSettle();

        expect(result, isNotNull, reason: reason);
        expect(result!.size, entry.key, reason: reason);
      }
    });
  });
}

/// Харнесс: открывает пикер как modal sheet и отдаёт результат наружу.
Widget _sheetLauncher({
  required double initialSize,
  required ValueChanged<MarkerStyleSelection?> onResult,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final selection = await MarkerStylePickerSheet.show(
                  context,
                  point: const LatLng(0, 0),
                  initialShape: 'pin',
                  initialColor: '#C4956A',
                  initialSize: initialSize,
                );
                onResult(selection);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
