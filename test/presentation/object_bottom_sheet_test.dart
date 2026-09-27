import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/presentation/widgets/app_scroll.dart';
import 'package:digger_maps/presentation/widgets/bottom_sheets/marker_style_picker_sheet.dart';
import 'package:digger_maps/presentation/widgets/object_bottom_sheet.dart';

/// Открывает общую оболочку так же, как это делают реальные вызывающие —
/// через [showObjectBottomSheet] (нативная ручка + `enableDrag: false`).
Future<void> _openSheet(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    scrollBehavior: appScrollBehavior,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showObjectBottomSheet<void>(
              context: context,
              builder: (_) => ObjectBottomSheet(child: child),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('перетаскивание стоковой ручки вниз закрывает лист',
      (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, const SizedBox(height: 120, child: Text('Форма')));
    expect(find.byType(ObjectBottomSheet), findsOneWidget);

    // Ручка — единственная интерактивная область закрытия, её даёт modal route.
    final handle = find.bySemanticsLabel('Dismiss');
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.byType(ObjectBottomSheet), findsNothing,
        reason: 'Перетаскивание ручки должно закрыть маршрут');
  });

  testWidgets('перетаскивание формы прокручивает её, но не закрывает лист',
      (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(
      tester,
      Column(
        children: <Widget>[
          for (var i = 0; i < 40; i++)
            SizedBox(height: 40, child: Text('row $i')),
        ],
      ),
    );

    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    await tester.drag(find.text('row 0'), const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(find.byType(ObjectBottomSheet), findsOneWidget,
        reason: 'Вертикальный жест по форме не должен тянуть лист');
    expect(position.pixels, greaterThan(0),
        reason: 'Форма должна прокрутиться');
  });

  testWidgets('в листе ровно одна нативная ручка', (tester) async {
    await _openSheet(tester, const SizedBox(height: 80, child: Text('x')));

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss'), findsOneWidget,
        reason: 'Оболочка не рисует вторую ручку поверх стоковой');
  });

  testWidgets('общий пикер стиля тоже закрывается ручкой', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      scrollBehavior: appScrollBehavior,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => MarkerStylePickerSheet.show(
                context,
                point: const LatLng(0, 0),
                initialShape: 'pin',
                initialColor: '#C4956A',
                initialSize: 32,
              ),
              child: const Text('Стиль'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Стиль'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkerStylePickerSheet), findsOneWidget);

    await tester.drag(find.bySemanticsLabel('Dismiss'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.byType(MarkerStylePickerSheet), findsNothing);
  });

  testWidgets('оболочка резервирует правый gutter под scrollbar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ObjectBottomSheet(child: Text('контент'))),
    ));

    final view = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final padding = view.padding! as EdgeInsets;
    expect(padding.right, 16 + kAppScrollbarGutter);
  });

  testWidgets('переполненная оболочка показывает одну полосу прокрутки',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ObjectBottomSheet(
          child: Column(
            children: <Widget>[
              for (var i = 0; i < 60; i++)
                SizedBox(height: 40, child: Text('row $i')),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isTrue,
    );
  });
}
