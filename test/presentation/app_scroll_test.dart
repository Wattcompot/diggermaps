import 'package:digger_maps/presentation/widgets/app_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _tallItem(BuildContext context, int index) =>
    SizedBox(height: 48, child: Text('item $index'));

void main() {
  testWidgets('AppScrollView показывает scrollbar при overflow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: AppScrollView(itemCount: 60, itemBuilder: _tallItem),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.controller, isNotNull);
  });

  testWidgets('AppScrollView резервирует правый gutter под полосу',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: AppScrollView(
          itemCount: 3,
          itemBuilder: (context, index) =>
              SizedBox(height: 24, child: Text('item $index')),
        ),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(find.byType(ListView));
    final padding = list.padding! as EdgeInsets;
    expect(padding.right, kAppScrollbarGutter);
  });

  testWidgets('thumb скрыт, когда содержимое помещается во вьюпорт',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: AppScrollView(
          itemCount: 2,
          itemBuilder: (context, index) =>
              SizedBox(height: 24, child: Text('item $index')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isFalse);
  });

  testWidgets('app-wide поведение оборачивает вертикальный список',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: ListView(
          children: <Widget>[
            for (var i = 0; i < 40; i++)
              SizedBox(height: 40, child: Text('row $i')),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('горизонтальный список полосы не получает', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: Center(
          child: SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (var i = 0; i < 40; i++)
                  const SizedBox(width: 80, child: Text('col')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('вложенный вертикальный список не получает вторую полосу',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: AppScrollView(
          itemCount: 20,
          itemBuilder: (context, index) => SizedBox(
            height: 48,
            child: AppScrollView(
              shrinkWrap: true,
              itemCount: 5,
              itemBuilder: (innerContext, innerIndex) =>
                  const SizedBox(height: 20, child: Text('nested')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
