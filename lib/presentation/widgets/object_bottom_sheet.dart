import 'package:flutter/material.dart';

import 'app_scroll.dart';

const objectEditorColors = <Color>[
  Color(0xFFFF0000),
  Color(0xFF2196F3),
  Color(0xFF00A651),
  Color(0xFFFFEB3B),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFFFFFFFF),
];

/// Открывает [ObjectBottomSheet] как modal bottom sheet со стоковой ручкой
/// перетаскивания Material.
///
/// Почему именно так:
///  * `showDragHandle: true` рисует нативную ручку, а `enableDrag: true` вешает
///    штатный жест листа на всю его площадь — тянуть вниз можно с любого места,
///    а не только за ручку;
///  * `isScrollControlled: true` оставлен, чтобы лист занимал столько, сколько
///    нужно содержимому.
///
/// Как это уживается с прокруткой формы: `Scrollable` регистрирует жест
/// вертикального драга только когда содержимое реально переполняет лист
/// (`shouldAcceptUserOffset`). Поэтому:
///  * форма помещается — вертикальный жест в любом месте тянет сам лист;
///  * форма длиннее листа — жест по форме прокручивает её, а жест по шапке,
///    ручке, отступам и кнопкам по-прежнему тянет лист;
///  * вытягивание вниз в самом верху прокрученного списка дообрабатывает
///    [ObjectBottomSheet] и закрывает лист (см. `_onScrollNotification`).
Future<T?> showObjectBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: true,
      // Плавное появление/закрытие вместо резкого старта анимации.
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    );

/// Общая оболочка редакторов объектов.
///
/// Содержимое остаётся локальным для каждого объекта, а оболочка даёт
/// корректные ограничения по высоте, безопасную прокрутку, место под
/// вертикальный scrollbar и закрытие вытягиванием вниз в самом верху списка.
///
/// Важно: собственный `Scrollbar` здесь НЕ добавляется — полосу вводит
/// централизованно `ScrollConfiguration(appScrollBehavior)` (см. ниже), поэтому
/// дублировать её нельзя. Ручка перетаскивания тоже не рисуется: её даёт
/// нативный modal route через [showObjectBottomSheet].
class ObjectBottomSheet extends StatefulWidget {
  const ObjectBottomSheet({
    super.key,
    required this.child,
    this.backgroundColor,
    this.maxHeightFactor = 0.88,
    this.scrollController,
    this.physics,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final Widget child;
  final Color? backgroundColor;
  final double maxHeightFactor;
  final ScrollController? scrollController;

  /// Физика прокрутки при переполнении. По умолчанию — [ClampingScrollPhysics].
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  @override
  State<ObjectBottomSheet> createState() => _ObjectBottomSheetState();
}

class _ObjectBottomSheetState extends State<ObjectBottomSheet>
    with SingleTickerProviderStateMixin {
  ScrollController? _ownedController;
  ScrollController get _controller =>
      widget.scrollController ?? (_ownedController ??= ScrollController());

  /// Смещение листа вниз, пока пользователь вытягивает его из начала списка.
  ///
  /// Нативный жест (`enableDrag`) двигает лист сам; здесь обрабатывается только
  /// тот случай, когда жест начался по прокручиваемому содержимому и список уже
  /// стоит в самом верху — тогда прокрутка «упирается» и жест транслируется в
  /// смещение листа.
  double _pullOffset = 0;
  bool _overscrollDrag = false;
  bool _dismissed = false;

  // Контроллер докрутки создаётся в initState (а не как `late final` с ленивой
  // инициализацией): иначе, если пользователь ни разу не тянул лист, первое
  // обращение к нему происходило бы в dispose() — создание тикера ищет
  // TickerMode на уже деактивированном элементе и падает с «Looking up a
  // deactivated widget's ancestor is unsafe».
  late final AnimationController _settle;
  Tween<double> _settleTween = Tween<double>(begin: 0, end: 0);

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() => _pullOffset = _settleTween.evaluate(_settle));
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  // --------------------------------------------------- pull-down из списка

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is OverscrollNotification) {
      // Пользователь тянет список ниже нулевой позиции: транслируем этот
      // сдвиг в смещение всего листа (как в DraggableScrollableSheet).
      if (notification.overscroll < 0 && notification.dragDetails != null) {
        _overscrollDrag = true;
        _settle.stop();
        _applyPull(-notification.overscroll);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification && _overscrollDrag) {
      // Палец пошёл обратно вверх, пока лист смещён: сначала убираем смещение.
      final delta = notification.scrollDelta ?? 0;
      if (delta > 0 && _pullOffset > 0) _applyPull(-delta);
      return false;
    }
    if (notification is ScrollEndNotification && _overscrollDrag) {
      _overscrollDrag = false;
      _finishPull(notification.dragDetails?.primaryVelocity ?? 0);
      return false;
    }
    return false;
  }

  void _applyPull(double delta) {
    final next = (_pullOffset + delta).clamp(0.0, double.infinity);
    if (next == _pullOffset) return;
    setState(() => _pullOffset = next);
  }

  void _finishPull(double velocity) {
    if (_dismissed || !mounted) return;
    final height = context.size?.height ?? 0;
    final threshold = height > 0 ? height * 0.3 : 120.0;
    if (_pullOffset > threshold || (velocity > 700 && _pullOffset > 24)) {
      _dismissed = true;
      Navigator.of(context).maybePop();
      return;
    }
    _settleTween = Tween<double>(begin: _pullOffset, end: 0);
    _settle.forward(from: 0);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight =
        MediaQuery.sizeOf(context).height * widget.maxHeightFactor;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    // Резервируем правый gutter под scrollbar, чтобы полоса не перекрывала
    // содержимое формы. Нижний отступ учитывает клавиатуру.
    final padding = widget.padding
        .add(EdgeInsets.only(right: kAppScrollbarGutter, bottom: keyboard));

    final sheet = Material(
      color: widget.backgroundColor ?? theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ScrollConfiguration(
            // Даём полосу даже там, где `MaterialApp.scrollBehavior` не задан
            // (например, изолированные тесты), и не дублируем её во вложенных
            // прокрутках — за это отвечает [AppScrollbarScope].
            behavior: appScrollBehavior,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: SingleChildScrollView(
                controller: _controller,
                primary: false,
                padding: padding,
                physics: widget.physics ?? const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );

    if (_pullOffset == 0) return sheet;
    return Transform.translate(offset: Offset(0, _pullOffset), child: sheet);
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
