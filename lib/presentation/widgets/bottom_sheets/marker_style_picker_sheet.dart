import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../object_bottom_sheet.dart';
import '../poi/marker_builder.dart';
import '../poi/marker_shape.dart';

class MarkerStyleSelection {
  const MarkerStyleSelection(
      {required this.shape, required this.colorHex, required this.size});
  final String shape;
  final String colorHex;
  final double size;
}

class MarkerStylePickerSheet extends StatefulWidget {
  const MarkerStylePickerSheet(
      {super.key,
      required this.point,
      required this.initialShape,
      required this.initialColor,
      required this.initialSize,
      this.previewBuilder});

  final LatLng point;
  final String initialShape;
  final String initialColor;
  final double initialSize;
  final Widget Function(String shape, String colorHex, double size)?
      previewBuilder;

  static Future<MarkerStyleSelection?> show(
    BuildContext context, {
    required LatLng point,
    required String initialShape,
    required String initialColor,
    required double initialSize,
    Widget Function(String shape, String colorHex, double size)? previewBuilder,
  }) =>
      showModalBottomSheet<MarkerStyleSelection>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MarkerStylePickerSheet(
            point: point,
            initialShape: initialShape,
            initialColor: initialColor,
            initialSize: initialSize,
            previewBuilder: previewBuilder),
      );

  @override
  State<MarkerStylePickerSheet> createState() => _MarkerStylePickerSheetState();
}

class _MarkerStylePickerSheetState extends State<MarkerStylePickerSheet> {
  static const _shapes = <String, String>{
    'pin': 'Метка',
    'star': 'Звезда',
    'flag': 'Флаг',
    'home': 'Дом',
    'work': 'Работа',
    'circle': 'Круг',
    'square': 'Квадрат',
    'triangle': 'Треугольник',
  };
  static const _colors = <String, String>{
    '#C4956A': 'Коричневый',
    '#A67B5B': 'Тёмно-коричневый',
    '#F44336': 'Красный',
    '#2196F3': 'Синий',
    '#4CAF50': 'Зелёный',
    '#FFEB3B': 'Жёлтый',
    '#FF9800': 'Оранжевый',
    '#9C27B0': 'Фиолетовый',
    '#FFFFFF': 'Белый',
  };
  late String _shape;
  late String _color;
  late double _size;
  bool _showShapes = false;
  bool _showColors = false;

  @override
  void initState() {
    super.initState();
    _shape = widget.initialShape;
    _color = widget.initialColor;
    _size = widget.initialSize;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObjectBottomSheet(
        child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Внешний вид', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text('Предпросмотр', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Container(
          height: 132,
          decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: _size, end: _size),
            duration: const Duration(milliseconds: 180),
            builder: (context, size, _) =>
                widget.previewBuilder?.call(_shape, _color, size) ??
                Center(
                    child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: MarkerShape(
                      key: ValueKey('$_shape:$_color'),
                      shape: _shape,
                      color: MarkerBuilder.parseColorHex(_color),
                      size: size),
                )),
          ),
        ),
        const SizedBox(height: 8),
        _expander('Форма', _shapes[_shape] ?? 'Метка', _showShapes,
            () => setState(() => _showShapes = !_showShapes)),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: !_showShapes
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _shapes.entries
                      .map((entry) => Tooltip(
                            message: entry.value,
                            child: InkWell(
                              onTap: () => setState(() => _shape = entry.key),
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 56,
                                height: 48,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: _shape == entry.key
                                        ? theme.colorScheme.primary
                                            .withValues(alpha: .2)
                                        : null,
                                    border: Border.all(
                                        color: _shape == entry.key
                                            ? theme.colorScheme.primary
                                            : theme.dividerColor)),
                                child: Center(
                                    child: MarkerShape(
                                        shape: entry.key,
                                        color:
                                            MarkerBuilder.parseColorHex(_color),
                                        size: 26)),
                              ),
                            ),
                          ))
                      .toList(),
                ),
        ),
        _expander('Цвет', _colors[_color] ?? 'Выбранный', _showColors,
            () => setState(() => _showColors = !_showColors)),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: !_showColors
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _colors.entries
                      .map((entry) => Tooltip(
                            message: entry.value,
                            child: InkWell(
                              onTap: () => setState(() => _color = entry.key),
                              customBorder: const CircleBorder(),
                              child: SizedBox.square(
                                  dimension: 44,
                                  child: Center(
                                      child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: MarkerBuilder.parseColorHex(
                                            entry.key),
                                        border: Border.all(
                                            color: _color == entry.key
                                                ? theme.colorScheme.onSurface
                                                : theme.dividerColor,
                                            width:
                                                _color == entry.key ? 3 : 1)),
                                    child: _color == entry.key
                                        ? Icon(Icons.check,
                                            size: 18,
                                            color: ThemeData
                                                        .estimateBrightnessForColor(
                                                            MarkerBuilder
                                                                .parseColorHex(
                                                                    entry
                                                                        .key)) ==
                                                    Brightness.light
                                                ? Colors.black
                                                : Colors.white)
                                        : null,
                                  ))),
                            ),
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        Text('Размер', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final entry in <double, String>{
            24: 'Маленький',
            32: 'Средний',
            48: 'Большой'
          }.entries)
            ChoiceChip(
                label: Text(entry.value),
                selected: _closestSize(_size) == entry.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _size = entry.key)),
        ]),
        const SizedBox(height: 12),
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  MarkerStyleSelection(
                      shape: _shape, colorHex: _color, size: _size)),
              child: const Text('Готово'),
            )),
      ],
    ));
  }

  Widget _expander(
          String title, String value, bool expanded, VoidCallback onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(value),
        onTap: onTap,
        trailing: AnimatedRotation(
            turns: expanded ? .25 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(Icons.chevron_right)),
      );

  static double _closestSize(double size) => size < 28
      ? 24
      : size < 40
          ? 32
          : 48;
}
