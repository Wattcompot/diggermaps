import 'package:digger_maps/presentation/widgets/app_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required Widget home}) => MaterialApp(
      builder: (context, child) =>
          AppNotificationsHost(child: child ?? const SizedBox.shrink()),
      home: home,
    );

void main() {
  testWidgets('SnackBar показывается через общий хост', (tester) async {
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppNotifications.show(
                context,
                const SnackBar(content: Text('Единое уведомление')),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Единое уведомление'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('хост не перехватывает нажатия вне самого уведомления',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(child: Center(child: Text('карта'))),
          ),
        ),
      ),
    );

    await tester.tap(find.text('карта'));
    expect(taps, 1);

    // Уведомление не показано — над Navigator нет ни одного перехватчика.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('поверх диалога уведомление одно и живёт в хосте над Navigator',
      (tester) async {
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Диалог'),
                  content: TextButton(
                    onPressed: () => AppNotifications.show(
                      dialogContext,
                      const SnackBar(content: Text('Поверх диалога')),
                    ),
                    child: const Text('notify'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Диалог'), findsOneWidget);

    await tester.tap(find.text('notify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Ровно одно уведомление: вложенный Scaffold экрана его не дублирует.
    expect(find.text('Поверх диалога'), findsOneWidget);

    // Уведомление принадлежит Scaffold хоста, а сам диалог лежит внутри
    // Navigator, который является body этого Scaffold: значит слой уведомления
    // выше модального слоя.
    final hostScaffold = find
        .ancestor(of: find.byType(SnackBar), matching: find.byType(Scaffold))
        .first;
    expect(hostScaffold, findsOneWidget);

    final navigatorInHost = find.descendant(
      of: hostScaffold,
      matching: find.byType(Navigator),
    );
    expect(navigatorInHost, findsOneWidget);

    expect(
      find.descendant(of: navigatorInHost, matching: find.text('Диалог')),
      findsOneWidget,
    );
  });

  testWidgets('вложенный Scaffold экрана не дублирует уведомление',
      (tester) async {
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppNotifications.message(context, 'Один раз'),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Один раз'), findsOneWidget);
  });

  testWidgets('уведомление из Drawer не перехватывается вложенным Scaffold',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppNotificationsHost(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          key: scaffoldKey,
          drawer: Builder(
            builder: (context) => Drawer(
              child: TextButton(
                onPressed: () => AppNotifications.message(context, 'Из drawer'),
                child: const Text('notify'),
              ),
            ),
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('notify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Из drawer'), findsOneWidget);
  });

  testWidgets('hideCurrent скрывает текущее уведомление', (tester) async {
    late BuildContext savedContext;
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              savedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    AppNotifications.show(
      savedContext,
      const SnackBar(content: Text('Скрыть меня')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Скрыть меня'), findsOneWidget);

    AppNotifications.hideCurrent(savedContext);
    await tester.pumpAndSettle();
    expect(find.text('Скрыть меня'), findsNothing);
  });
}
