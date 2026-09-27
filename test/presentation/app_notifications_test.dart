import 'package:digger_maps/presentation/widgets/app_notifications.dart';
import 'package:digger_maps/theme/app_theme.dart';
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

  testWidgets('нижний слот хоста не меняет MediaQuery потомков',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      _host(home: Scaffold(body: SizedBox.expand(key: key))),
    );

    expect(MediaQuery.of(key.currentContext!).padding.bottom, 24);

    // Слот высотой с нижние контролы: потомки всё равно видят исходный
    // safe-area, иначе карта и bottom-sheet'ы уезжали бы вверх.
    AppNotifications.bottomInset.value = 240;
    await tester.pump();

    expect(MediaQuery.of(key.currentContext!).padding.bottom, 24);
    expect(MediaQuery.of(key.currentContext!).viewPadding.bottom, 24);
  });

  testWidgets('уведомление поднимается над нижним слотом хоста',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      _host(home: Scaffold(body: SizedBox.expand(key: key))),
    );

    AppNotifications.bottomInset.value = 200;
    await tester.pump();

    AppNotifications.show(
      key.currentContext!,
      const SnackBar(content: Text('Над кнопками')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final snack = tester.getRect(find.byType(SnackBar));
    // Низ экрана (800) минус высота слота (200).
    expect(snack.bottom, lessThanOrEqualTo(600 + 0.1));
    expect(snack.top, greaterThan(0));
  });

  testWidgets('themedSnackBarHeight не занижает реальную высоту',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const text = 'Перемещайте карту под прицелом и нажмите «Готово»';
    final key = GlobalKey();
    late double estimate;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) =>
            AppNotificationsHost(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) {
            estimate = AppNotifications.themedSnackBarHeight(context, text);
            return Scaffold(body: SizedBox.expand(key: key));
          },
        ),
      ),
    );

    AppNotifications.show(
        key.currentContext!, const SnackBar(content: Text(text)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final actual = tester.getRect(find.byType(SnackBar)).height;
    // Запас должен покрывать реальную плашку (иначе прицел перекроется),
    // но не раздуваться сверх неё.
    expect(estimate, greaterThanOrEqualTo(actual - 0.1));
    expect(estimate, lessThanOrEqualTo(actual + 12));
  });

  testWidgets('без дока уведомление всё равно поднимается над клавиатурой',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(key: key),
        ),
      ),
    );

    AppNotifications.show(
      key.currentContext!,
      const SnackBar(content: Text('Над клавиатурой')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Клавиатура занимает нижние 300 px — уведомление целиком выше неё, хотя
    // экран не сообщал высоту нижнего дока (inset == 0).
    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(800 - 300 + 0.1));
    expect(snack.top, greaterThanOrEqualTo(0));
  });

  testWidgets('слот берёт максимум из высоты дока и клавиатуры',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(key: key),
        ),
      ),
    );

    // Док выше клавиатуры: слот = max(400, 300) = 400, уведомление над доком.
    AppNotifications.bottomInset.value = 400;
    await tester.pump();

    AppNotifications.show(
      key.currentContext!,
      const SnackBar(content: Text('Над доком')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(800 - 400 + 0.1));
  });

  testWidgets(
      'клавиатура и нижний док не меняют геометрию и MediaQuery потомков',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);

    final bodyKey = GlobalKey();
    await tester.pumpWidget(
      _host(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(key: bodyKey),
        ),
      ),
    );

    final baseline = tester.getRect(find.byKey(bodyKey));
    expect(baseline, const Rect.fromLTWH(0, 0, 400, 800));

    // Клавиатура (300) + safe area (24) + нижний док (200).
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    AppNotifications.bottomInset.value = 200;
    await tester.pump();

    // Body хоста не сжался и не сдвинулся: слот влияет только на SnackBar.
    expect(tester.getRect(find.byKey(bodyKey)), baseline);

    // Потомки видят исходный MediaQuery: настоящую клавиатуру и safe area, а не
    // высоту слота хоста.
    final mediaQuery = MediaQuery.of(bodyKey.currentContext!);
    expect(mediaQuery.padding.bottom, 24);
    expect(mediaQuery.viewPadding.bottom, 24);
    expect(mediaQuery.viewInsets.bottom, 300);

    AppNotifications.show(
      bodyKey.currentContext!,
      const SnackBar(content: Text('Над клавиатурой и доком')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Уведомление целиком выше и клавиатуры (800 - 300), и дока (800 - 200).
    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(800 - 300 + 0.1));
    expect(snack.bottom, lessThanOrEqualTo(800 - 200 + 0.1));
    expect(snack.top, greaterThanOrEqualTo(0));
  });

  testWidgets(
      'над модальным маршрутом уведомление тоже уходит из-под клавиатуры',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

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
                      const SnackBar(content: Text('Поверх модалки')),
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

    expect(find.text('Поверх модалки'), findsOneWidget);

    // Уведомление целиком выше клавиатуры...
    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(800 - 300 + 0.1));

    // ...и по-прежнему живёт в хосте над Navigator, то есть выше модального слоя.
    final hostScaffold = find
        .ancestor(of: find.byType(SnackBar), matching: find.byType(Scaffold))
        .first;
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

  testWidgets(
      'AppNotificationBottomInset учитывает изменение extraBottom без смены размера',
      (tester) async {
    addTearDown(() => AppNotifications.bottomInset.value = 0);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var extraBottom = 10.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _host(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AppNotificationBottomInset(
                  extraBottom: extraBottom,
                  child: const SizedBox(height: 100, width: 400),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();
    expect(AppNotifications.bottomInset.value, closeTo(110, 0.5));

    // Меняется только extraBottom; размер ребёнка (100) остаётся прежним, так
    // что layout не перезапускается — высота должна обновиться всё равно.
    extraBottom = 40;
    rebuild(() {});
    await tester.pump();
    await tester.pump();

    expect(AppNotifications.bottomInset.value, closeTo(140, 0.5));
  });
}
