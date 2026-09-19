import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

const objectEditorColors = <Color>[
  Color(0xFFFF0000),
  Color(0xFF2196F3),
  Color(0xFF00A651),
  Color(0xFFFFEB3B),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFFFFFFFF),
];

/// Общая оболочка редакторов объектов.
///
/// Содержимое остаётся локальным для каждого объекта, а оболочка даёт
/// ручку перетаскивания, корректные ограничения по высоте, прокрутку и
/// закрытие свайпом вниз.
///
/// Почему свайп не работал: внутри лежал `SingleChildScrollView` с
/// `ClampingScrollPhysics`, который всегда выигрывал вертикальный drag у
/// `BottomSheet`, даже когда прокручивать было нечего. Теперь:
///
///  * пока содержимое помещается — прокрутка выключена, и весь лист тянется
///    целиком (внешний [GestureDetector]);
///  * когда содержимое переполняет лист — оно прокручивается, а лист тянется
///    за ручку либо при overscroll вверху списка (перетаскивание «выше нуля»
///    транслируется в смещение листа);
///  * достаточный сдвиг или быстрый флик вниз закрывают лист, иначе он
///    плавно возвращается на место.
///
/// Важно: собственный `Scrollbar` здесь НЕ добавляется — глобальное
/// `ScrollBehavior` вводит прокруточную полосу централизованно, поэтому
/// дублировать её нельзя.
class ObjectBottomSheet extends StatefulWidget {
  const ObjectBottomSheet({
    super.key,
    required this.child,
    this.backgroundColor,
    this.maxHeightFactor = 0.88,
    this.scrollController,
    this.physics,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.dismissible = true,
  });

  final Widget child;
  final Color? backgroundColor;
  final double maxHeightFactor;
  final ScrollController? scrollController;

  /// Физика прокрутки при переполнении. По умолчанию — [ClampingScrollPhysics].
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  /// Разрешить закрытие свайпом вниз.
  final bool dismissible;

  @override
  State<ObjectBottomSheet> createState() => _ObjectBottomSheetState();
}

class _ObjectBottomSheetState extends State<ObjectBottomSheet>
    with SingleTickerProviderStateMixin {
  ScrollController? _ownedController;
  ScrollController get _controller =>
      widget.scrollController ?? (_ownedController ??= ScrollController());

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() {
      setState(() => _offset = _settleTween.evaluate(_settle));
    });
  Tween<double> _settleTween = Tween<double>(begin: 0, end: 0);

  /// Текущее смещение листа вниз (лог. пиксели).
  double _offset = 0;

  /// Прокручивается ли содержимое (переполняет ли максимальную высоту).
  bool _overflow = false;

  /// Идёт ли перетаскивание за счёт overscroll списка.
  bool _overscrollDrag = false;
  double _lastOverscrollVelocity = 0;

  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    // Initialise the ticker while the element is active, even without a drag.
    _settle;
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant ObjectBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _settle.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- overflow

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.positions.length != 1) return;
      final position = _controller.positions.first;
      if (!position.hasContentDimensions) return;
      _applyOverflow(position.maxScrollExtent > position.minScrollExtent);
    });
  }

  void _applyOverflow(bool next) {
    if (next == _overflow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next == _overflow) return;
      setState(() => _overflow = next);
    });
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    _applyOverflow(notification.metrics.maxScrollExtent >
        notification.metrics.minScrollExtent);
    return false;
  }

  // ------------------------------------------------------------ drag (sheet)

  void _onDragStart(DragStartDetails details) {
    _settle.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    _applyDrag(delta);
  }

  void _applyDrag(double delta) {
    final next = (_offset + delta).clamp(0.0, double.infinity);
    if (next == _offset) return;
    setState(() => _offset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    _finishDrag(details.primaryVelocity ?? 0);
  }

  void _finishDrag(double velocity) {
    if (_dismissed || !mounted) return;
    final height = context.size?.height ?? 0;
    final threshold = height > 0 ? height * 0.3 : 120.0;
    final shouldDismiss = widget.dismissible &&
        (_offset > threshold || (velocity > 700 && _offset > 24));
    if (shouldDismiss) {
      _dismissed = true;
      Navigator.of(context).maybePop();
      return;
    }
    _settleTween = Tween<double>(begin: _offset, end: 0);
    _settle
      ..duration = const Duration(milliseconds: 220)
      ..forward(from: 0);
  }

  // ------------------------------------------------------- drag (overscroll)

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_overflow) return false;
    if (notification is OverscrollNotification) {
      // Пользователь тянет список ниже нулевой позиции: транслируем сдвиг в
      // смещение всего листа — как в DraggableScrollableSheet.
      if (notification.overscroll < 0 && notification.dragDetails != null) {
        _overscrollDrag = true;
        _settle.stop();
        _applyDrag(-notification.overscroll);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification && _overscrollDrag) {
      // Палец пошёл обратно вверх, пока лист смещён: убираем смещение до
      // того, как список начнёт прокручиваться.
      final delta = notification.scrollDelta ?? 0;
      if (delta > 0 && _offset > 0) _applyDrag(-delta);
      return false;
    }
    if (notification is ScrollEndNotification && _overscrollDrag) {
      _overscrollDrag = false;
      final velocity =
          notification.dragDetails?.primaryVelocity ?? _lastOverscrollVelocity;
      _lastOverscrollVelocity = 0;
      _finishDrag(velocity);
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle &&
        _overscrollDrag) {
      _overscrollDrag = false;
      _finishDrag(0);
    }
    return false;
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight =
        MediaQuery.sizeOf(context).height * widget.maxHeightFactor;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final handle = Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade600,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );

    final scrollable = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: SingleChildScrollView(
          controller: _controller,
          primary: false,
          padding: widget.padding.add(EdgeInsets.only(bottom: keyboard)),
          // Пока содержимое помещается — прокрутки нет, и лист тянется целиком.
          physics: _overflow
              ? (widget.physics ?? const ClampingScrollPhysics())
              : const NeverScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: widget.child,
        ),
      ),
    );

    Widget sheet = Material(
      color: widget.backgroundColor ?? theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Ручка всегда тянет лист, даже когда список прокручивается.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: SizedBox(width: double.infinity, child: handle),
              ),
              Flexible(child: scrollable),
            ],
          ),
        ),
      ),
    );

    if (widget.dismissible) {
      // Внешний детектор получает drag, когда прокрутка выключена (содержимое
      // помещается). При переполнении арену выигрывает список, а лист
      // двигается через overscroll (см. [_onScroll]).
      sheet = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: sheet,
      );
    }

    return Transform.translate(
      offset: Offset(0, _offset),
      child: sheet,
    );
  }
}

class ObjectEditorFields extends StatelessWidget {
  const ObjectEditorFields({
    super.key,
    required this.nameController,
    required this.descriptionController,
    required this.leading,
    this.trailing,
    this.colors = const <Color>[],
    this.selectedColor,
    this.onColorSelected,
    this.strokeWidth,
    this.onStrokeWidthChanged,
    this.minStrokeWidth = 1,
    this.maxStrokeWidth = 12,
    this.visible,
    this.onVisibilityChanged,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final Widget leading;
  final Widget? trailing;
  final List<Color> colors;
  final Color? selectedColor;
  final ValueChanged<Color>? onColorSelected;

  /// Толщина линии: показываем слайдер только если задан [onStrokeWidthChanged].
  final double? strokeWidth;
  final ValueChanged<double>? onStrokeWidthChanged;
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final bool? visible;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    final showWidth = strokeWidth != null && onStrokeWidthChanged != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: nameController,
                style: TextStyle(color: foreground),
                decoration: const InputDecoration(
                  labelText: 'Название',
                  isDense: true,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descriptionController,
          minLines: 1,
          maxLines: 3,
          style: TextStyle(color: foreground),
          decoration: const InputDecoration(
            labelText: 'Описание',
            isDense: true,
          ),
        ),
        if (colors.isNotEmpty && onColorSelected != null) ...[
          const SizedBox(height: 14),
          Text('Цвет', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: colors.map((color) {
              final selected = color.toARGB32() == selectedColor?.toARGB32();
              return InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onColorSelected!(color),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : theme.dividerColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
        if (showWidth) ...[
          const SizedBox(height: 14),
          Text(
            'Толщина: ${strokeWidth!.toStringAsFixed(0)}',
            style: theme.textTheme.labelLarge,
          ),
          Slider(
            value: strokeWidth!.clamp(minStrokeWidth, maxStrokeWidth),
            min: minStrokeWidth,
            max: maxStrokeWidth,
            divisions: ((maxStrokeWidth - minStrokeWidth) * 2).round(),
            activeColor: selectedColor,
            onChanged: onStrokeWidthChanged,
          ),
        ],
        if (visible != null && onVisibilityChanged != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Видимость на карте'),
            value: visible!,
            onChanged: onVisibilityChanged,
          ),
      ],
    );
  }
}
