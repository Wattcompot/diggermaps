import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Единый канал показа [SnackBar] для всего приложения.
///
/// Проблема: `ScaffoldMessenger.of(context)` из контекста экрана показывает
/// сообщение внутри [Scaffold] этого экрана, поэтому уведомление пропадает под
/// открытым диалогом / bottom sheet / drawer.
///
/// Решение: в [MaterialApp.builder] над [Navigator] ставится
/// [AppNotificationsHost] — один общий [ScaffoldMessenger] и один прозрачный
/// [Scaffold]. Flutter при nested-скаффолдах показывает SnackBar только в
/// «корневом» Scaffold набора (`ScaffoldMessengerState._isRoot`), а корневой
/// здесь — именно хост над [Navigator]. Поэтому:
///
///  * уведомление рисуется поверх всех маршрутов, диалогов, bottom sheet и
///    drawer: слот `snackBar` у [Scaffold] лежит выше `body`, а `body` хоста —
///    это сам [Navigator];
///  * вложенные Scaffold экранов не дублируют сообщение;
///  * фон хоста прозрачный, а единственный элемент над [Navigator] — сам
///    SnackBar, поэтому хоста не перехватывает нажатия;
///  * сохраняются стандартные очередь, длительность, dismiss, action и анимации
///    [ScaffoldMessenger].
///
/// Публичный API: [show], [message], [hideCurrent], [removeCurrent].
class AppNotifications {
  AppNotifications._();

  /// Ключ общего [ScaffoldMessenger], установленного в [AppNotificationsHost].
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Высота нижних элементов управления экрана (дока кнопок карты, панели
  /// постановки метки, chip снимков и т.д.), над которыми должно висеть
  /// уведомление.
  ///
  /// Обновляется экраном через [AppNotificationBottomInset]; хост читает
  /// значение и приподнимает слот SnackBar на эту величину. Это общий
  /// механизм — не привязан к конкретному сообщению.
  static final ValueNotifier<double> bottomInset = ValueNotifier<double>(0);

  static ScaffoldMessengerState? _resolve(BuildContext context) =>
      messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);

  /// Показывает [snackBar] в общем хосте приложения.
  ///
  /// По умолчанию используется стандартная очередь [ScaffoldMessenger]; при
  /// `replace: true` текущее сообщение сначала скрывается стандартным
  /// [ScaffoldMessengerState.hideCurrentSnackBar] (поведение прежних вызовов
  /// `..hideCurrentSnackBar()..showSnackBar(...)`).
  static void show(
    BuildContext context,
    SnackBar snackBar, {
    bool replace = false,
  }) {
    final messenger = _resolve(context);
    if (messenger == null) return;
    if (replace) messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  /// Короткий вариант для текстового сообщения.
  static void message(
    BuildContext context,
    String text, {
    bool replace = false,
  }) {
    if (!context.mounted) return;
    show(context, SnackBar(content: Text(text)), replace: replace);
  }

  /// Скрывает текущее уведомление (с выходной анимацией).
  static void hideCurrent(
    BuildContext context, {
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) {
    _resolve(context)?.hideCurrentSnackBar(reason: reason);
  }

  /// Убирает текущее уведомление без анимации.
  static void removeCurrent(
    BuildContext context, {
    SnackBarClosedReason reason = SnackBarClosedReason.remove,
  }) {
    _resolve(context)?.removeCurrentSnackBar(reason: reason);
  }
}

/// Хост уведомлений: общий [ScaffoldMessenger] + прозрачный [Scaffold] над
/// [Navigator]. Подключается один раз в [MaterialApp.builder].
///
/// Над [Navigator] в дереве находится только слот `snackBar` этого Scaffold,
/// поэтому ничто, кроме реального уведомления, не может перехватить ввод.
class AppNotificationsHost extends StatelessWidget {
  const AppNotificationsHost({
    super.key,
    required this.child,
    this.messengerKey,
  });

  /// Обычно это `child` из [MaterialApp.builder] (то есть [Navigator]).
  final Widget child;

  /// Позволяет подменить ключ (используется в тестах); по умолчанию —
  /// [AppNotifications.messengerKey].
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey ?? AppNotifications.messengerKey,
      child: ValueListenableBuilder<double>(
        valueListenable: AppNotifications.bottomInset,
        builder: (context, inset, body) => Scaffold(
          // Прозрачный фон; body целиком занят Navigator, так что ввод достаётся
          // приложению, а snackBar рисуется отдельным слотом поверх body.
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          // Пустой прозрачный слот bottomNavigationBar высотой с нижние
          // контролы экрана: Scaffold поднимает SnackBar над этим слотом,
          // поэтому уведомление не перекрывает кнопки карты/панели. Слот не
          // перехватывает ввод, а body при этом всё равно растягивается на весь
          // экран (extendBody).
          extendBody: true,
          bottomNavigationBar: inset > 0
              ? IgnorePointer(
                  child: SizedBox(height: inset, width: double.infinity),
                )
              : null,
          body: body,
        ),
        child: child,
      ),
    );
  }
}

/// Сообщает [AppNotifications.bottomInset] фактическую высоту своего
/// содержимого (с учётом нижнего отступа [extraBottom]).
///
/// Оборачивает нижнюю стопку контролов экрана карты; при появлении/скрытии
/// панелей высота пересчитывается, и уведомления всегда висят над ней.
class AppNotificationBottomInset extends StatefulWidget {
  const AppNotificationBottomInset({
    super.key,
    required this.child,
    this.extraBottom = 0,
  });

  final Widget child;

  /// Расстояние от низа экрана до низа [child] (safe area + внешний отступ).
  final double extraBottom;

  @override
  State<AppNotificationBottomInset> createState() =>
      _AppNotificationBottomInsetState();
}

class _AppNotificationBottomInsetState
    extends State<AppNotificationBottomInset> {
  @override
  void dispose() {
    // Экран ушёл — уведомления возвращаются к обычному положению.
    AppNotifications.bottomInset.value = 0;
    super.dispose();
  }

  void _report(Size size) {
    final next = size.height + widget.extraBottom;
    if ((AppNotifications.bottomInset.value - next).abs() < 0.5) return;
    // Не меняем listenable во время layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppNotifications.bottomInset.value = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SizeReporter(onSize: _report, child: widget.child);
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (_last != size) {
      _last = size;
      onSize(size);
    }
  }
}
