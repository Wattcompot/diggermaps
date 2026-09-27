import 'dart:math' as math;

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
/// Публичный API: [show], [message], [hideCurrent], [removeCurrent], [clear].
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

  /// Окно подавления повторов: одинаковый текст, запрошенный снова в течение
  /// этого времени, не показывается повторно (двойной тап по кнопке, повторный
  /// тап по стабу «формат в разработке» и т.п.).
  static const Duration _dedupWindow = Duration(milliseconds: 2500);

  static String? _lastKey;
  static DateTime? _lastShownAt;

  static ScaffoldMessengerState? _resolve(BuildContext context) =>
      messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);

  /// Текст сообщения для дедупликации, если контент — обычный [Text].
  static String? _extractKey(SnackBar snackBar) {
    final content = snackBar.content;
    return content is Text ? content.data : null;
  }

  /// Показывает [snackBar] в общем хосте приложения.
  ///
  /// Поведение по умолчанию (`replace: true`) вытесняет текущее уведомление и
  /// всю ожидающую очередь ([ScaffoldMessengerState.clearSnackBars]) перед
  /// показом нового: статусные плашки и стабы не копятся и не «выстреливают»
  /// пачкой после закрытия меню/листа. Передайте `replace: false`, если нужно
  /// добавить сообщение в стандартную очередь, не трогая уже показанные.
  ///
  /// Повтор идентичного текста в пределах [_dedupWindow] игнорируется, поэтому
  /// многократный вызов одного и того же сообщения не мерцает и не заполняет
  /// очередь. Для нетекстового контента передайте [dedupKey] явно (иначе
  /// дедупликация для него не применяется). Разные сообщения по-прежнему
  /// показываются как обычно.
  static void show(
    BuildContext context,
    SnackBar snackBar, {
    bool replace = true,
    String? dedupKey,
  }) {
    final messenger = _resolve(context);
    if (messenger == null) return;

    final key = dedupKey ?? _extractKey(snackBar);
    final now = DateTime.now();
    if (key != null &&
        key == _lastKey &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupWindow) {
      // Тот же текст всё ещё актуален — продлеваем окно и выходим без показа.
      _lastShownAt = now;
      return;
    }
    _lastKey = key;
    _lastShownAt = now;

    if (replace) {
      messenger.clearSnackBars();
    }
    messenger.showSnackBar(snackBar);
  }

  /// Короткий вариант для текстового сообщения.
  static void message(
    BuildContext context,
    String text, {
    bool replace = true,
  }) {
    if (!context.mounted) return;
    show(context, SnackBar(content: Text(text)),
        replace: replace, dedupKey: text);
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

  /// Отменяет текущее уведомление и всю ожидающую очередь без анимации.
  ///
  /// Полезно при уходе с экрана/из меню, чтобы накопленные плашки не
  /// «выстреливали» следом. Сбрасывает и окно дедупликации.
  static void clear(BuildContext context) {
    _lastKey = null;
    _lastShownAt = null;
    _resolve(context)?.clearSnackBars();
  }

  /// Вертикальные отступы контента SnackBar внутри плашки (по 14 сверху и
  /// снизу в реализации Material). Учитываются в [themedSnackBarHeight].
  static const double _contentVerticalPadding = 14;

  /// Оценка высоты тематического floating [SnackBar] с текстом [text] при
  /// текущей ширине экрана и масштабе текста.
  ///
  /// Нужна экранам, которые резервируют место под уведомление: например,
  /// нижний док карты в режиме прицеливания укорачивается на эту величину,
  /// чтобы SnackBar встал над кнопками, но не залез на прицел.
  ///
  /// Значение выводится из темы ([SnackBarThemeData]: стиль контента,
  /// `insetPadding`, behavior) и фактического текста с учётом переноса строк,
  /// поэтому не зависит от конкретной модели устройства.
  static double themedSnackBarHeight(BuildContext context, String text) {
    final theme = Theme.of(context);
    final snackTheme = theme.snackBarTheme;
    final margin =
        snackTheme.insetPadding ?? const EdgeInsets.fromLTRB(15, 5, 15, 10);
    final horizontalPadding =
        snackTheme.behavior == SnackBarBehavior.fixed ? 24.0 : 16.0;
    final style = snackTheme.contentTextStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle();
    final contentWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width -
          margin.horizontal -
          horizontalPadding * 2,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: contentWidth);
    final contentHeight = painter.height;
    painter.dispose();
    return contentHeight +
        _contentVerticalPadding * 2 +
        margin.top +
        margin.bottom;
  }
}

/// Хост уведомлений: общий [ScaffoldMessenger] + прозрачный [Scaffold] над
/// [Navigator]. Подключается один раз в [MaterialApp.builder].
///
/// Над [Navigator] в дереве находится только слот `snackBar` этого Scaffold,
/// поэтому ничто, кроме реального уведомления, не может перехватить ввод.
///
/// Чтобы пустой нижний слот не смещал раскладку приложения, [Navigator]
/// оборачивается в исходный [MediaQueryData], снятый над этим Scaffold: слот
/// поднимает только SnackBar, а safe area, карта и bottom-sheet'ы видят
/// настоящие отступы экрана.
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
    // Снимок исходного MediaQuery ДО собственного Scaffold. Scaffold с
    // `extendBody`/`bottomNavigationBar` переписывает потомкам
    // `MediaQuery.padding.bottom` (подставляет высоту нижнего слота), из-за чего
    // SafeArea и bottom-sheet'ы внутри [Navigator] уезжали бы вверх. Возвращаем
    // дочернему дереву исходные данные: высота слота влияет только на положение
    // SnackBar, но не на карту, safe area и листы.
    final mediaQuery = MediaQuery.of(context);
    return ScaffoldMessenger(
      key: messengerKey ?? AppNotifications.messengerKey,
      child: ValueListenableBuilder<double>(
        valueListenable: AppNotifications.bottomInset,
        builder: (context, inset, body) {
          // Высота слота — максимум из высоты нижних контролов экрана ([inset])
          // и клавиатуры (`viewInsets.bottom`): Scaffold сажает SnackBar на верх
          // этого слота, поэтому уведомление не прячется под клавиатурой и не
          // перекрывает кнопки карты/панели. Оба отступа берутся из исходного
          // MediaQuery, так что клавиатура учитывается и без док-контролов.
          final slotHeight = math.max(inset, mediaQuery.viewInsets.bottom);
          return Scaffold(
            // Прозрачный фон; body целиком занят Navigator, так что ввод
            // достаётся приложению, а snackBar рисуется отдельным слотом поверх
            // body.
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            // Слот не перехватывает ввод, а body всё равно растягивается на весь
            // экран (extendBody) и не сжимается под клавиатуру
            // (`resizeToAvoidBottomInset: false`).
            extendBody: true,
            bottomNavigationBar: slotHeight > 0
                ? IgnorePointer(
                    child: SizedBox(
                      height: slotHeight,
                      width: double.infinity,
                    ),
                  )
                : null,
            body: MediaQuery(
              data: mediaQuery,
              child: body ?? const SizedBox.shrink(),
            ),
          );
        },
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
    // Виджет перестроился (например, изменился только `extraBottom`), а размер
    // ребёнка мог остаться прежним — тогда `performLayout` не вызовется и новая
    // суммарная высота потеряется. Повторно отдаём последний измеренный размер.
    renderObject.reportCurrentSize();
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  /// Повторно отдаёт [onSize] последний измеренный размер.
  ///
  /// Нужен, когда конфигурация виджета изменилась (например, `extraBottom`), а
  /// размер ребёнка — нет: в этом случае [performLayout] не вызывается, и без
  /// повторного отчёта суммарный отступ остался бы устаревшим.
  void reportCurrentSize() {
    if (hasSize) onSize(size);
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_last != size) {
      _last = size;
      onSize(size);
    }
  }
}
