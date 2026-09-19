import 'package:flutter/material.dart';

/// Общий [ScrollBehavior] приложения.
///
/// Зачем: длинные вертикальные меню, списки и диалоги должны иметь видимый
/// scrollbar, но только когда содержимое реально переполняет вьюпорт, и он не
/// должен дублироваться/накладываться для вложенных прокруток. Поведение
/// подключается один раз как `MaterialApp.scrollBehavior`, поэтому покрывает
/// все вертикальные списки, включая те, что создаются в чужих виджетах.
///
/// Особенности:
///  * горизонтальные прокрутки не трогаем;
///  * для вложенных прокруток (внутри уже обёрнутой [AppScrollbarScope])
///    полоса не создаётся — остаётся одна полоса на область;
///  * используется реальный контроллер из [ScrollableDetails], поэтому
///    несколько scroll client'ов не конфликтуют;
///  * толщина/цвет берутся из [ScrollbarTheme] (поддержка светлой/тёмной темы);
///  * thumb показывается только при overflow ([OverflowScrollbar]), а его
///    появление/скрытие анимируется стандартно.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return child;
    if (AppScrollbarScope.isNested(context)) return child;
    return AppScrollbarScope(
      child: OverflowScrollbar(details: details, child: child),
    );
  }
}

/// Экземпляр [AppScrollBehavior] для `MaterialApp(scrollBehavior: ...)` и
/// повторного использования в тестах.
const AppScrollBehavior appScrollBehavior = AppScrollBehavior();

/// Помечает поддерево как «уже со scrollbar'ом», чтобы вложенные вертикальные
/// прокрутки не рисовали вторую полосу поверх первой.
class AppScrollbarScope extends InheritedWidget {
  const AppScrollbarScope({super.key, required super.child});

  static bool isNested(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScrollbarScope>() != null;

  @override
  bool updateShouldNotify(AppScrollbarScope oldWidget) => false;
}

/// [Scrollbar] с видимым thumb'ом только тогда, когда содержимое прокручивается.
///
/// Стандартный [Scrollbar] с `thumbVisibility: true` на не-прокручиваемом
/// содержимом либо прячет полосу непредсказуемо, либо рисует полный трек.
/// Здесь наличие overflow определяется по метрикам, а переключение видимости
/// выполняет штатную fade-анимацию [Scrollbar].
class OverflowScrollbar extends StatefulWidget {
  const OverflowScrollbar({
    super.key,
    required this.details,
    required this.child,
  });

  final ScrollableDetails details;
  final Widget child;

  @override
  State<OverflowScrollbar> createState() => _OverflowScrollbarState();
}

class _OverflowScrollbarState extends State<OverflowScrollbar> {
  bool _overflow = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant OverflowScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.details.controller, widget.details.controller)) {
      _measurePosition();
    }
  }

  static bool _hasOverflow(ScrollMetrics metrics) =>
      metrics.maxScrollExtent > metrics.minScrollExtent;

  /// Метрики могут приходить во время layout, поэтому обновляем состояние
  /// в конце кадра.
  void _apply(bool next) {
    if (next == _overflow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next == _overflow) return;
      setState(() => _overflow = next);
    });
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePosition());
  }

  void _measurePosition() {
    if (!mounted) return;
    final controller = widget.details.controller;
    if (controller == null || !controller.hasClients) return;
    // Несколько позиций у одного контроллера — не наш случай, оставляем как есть.
    if (controller.positions.length != 1) return;
    final position = controller.positions.first;
    if (!position.hasContentDimensions) return;
    _apply(_hasOverflow(position));
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    _apply(_hasOverflow(notification.metrics));
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) _apply(_hasOverflow(notification.metrics));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Scrollbar(
          controller: widget.details.controller,
          thumbVisibility: _overflow,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Переиспользуемый вертикальный список с собственным контроллером и общим
/// scrollbar'ом.
///
/// Даёт «настоящий» [ScrollController] (или использует переданный), добавляет
/// правый gutter, чтобы полоса не перекрывала содержимое, и включает
/// [appScrollBehavior] даже там, где `MaterialApp.scrollBehavior` не задан
/// (например, в изолированных тестах).
class AppScrollView extends StatefulWidget {
  const AppScrollView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.scrollbarGutter = 8,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Внешний контроллер; если не задан — виджет владеет своим.
  final ScrollController? controller;

  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  /// Дополнительный отступ справа под вертикальный scrollbar.
  final double scrollbarGutter;

  @override
  State<AppScrollView> createState() => _AppScrollViewState();
}

class _AppScrollViewState extends State<AppScrollView> {
  ScrollController? _ownedController;

  ScrollController get _controller =>
      widget.controller ?? (_ownedController ??= ScrollController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final basePadding =
        widget.padding ?? const EdgeInsets.symmetric(vertical: 8);
    final padding = widget.scrollbarGutter <= 0
        ? basePadding
        : basePadding.add(EdgeInsets.only(right: widget.scrollbarGutter));

    return ScrollConfiguration(
      behavior: appScrollBehavior,
      child: ListView.builder(
        controller: _controller,
        primary: false,
        padding: padding,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}
