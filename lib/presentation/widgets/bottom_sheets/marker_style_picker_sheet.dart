import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../object_bottom_sheet.dart';

class MarkerStyleSelection {
  const MarkerStyleSelection({
    required this.shape,
    required this.colorHex,
    required this.size,
  });

  final String shape;
  final String colorHex;
  final double size;
}

class MarkerStylePickerSheet extends StatefulWidget {
  const MarkerStylePickerSheet({
    super.key,
    required this.point,
    required this.initialShape,
    required this.initialColor,
    required this.initialSize,
    this.previewBuilder,
  });

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
  }) {
    return showModalBottomSheet<MarkerStyleSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MarkerStylePickerSheet(
        point: point,
        initialShape: initialShape,
        initialColor: initialColor,
        initialSize: initialSize,
        previewBuilder: previewBuilder,
      ),
    );
  }

  @override
  State<MarkerStylePickerSheet> createState() => _MarkerStylePickerSheetState();
}

class _MarkerStylePickerSheetState extends State<MarkerStylePickerSheet> {
  static const _shapes = <String>[
    'pin',
    'star',
    'flag',
    'home',
    'work',
    'circle',
    'square',
    'triangle',
  ];
  static const _colors = <String>[
    '#A67B5B',
    '#F44336',
    '#2196F3',
    '#4CAF50',
    '#FFEB3B',
    '#FF9800',
    '#9C27B0',
    '#FFFFFF',
  ];

  late String _shape;
  late String _color;
  late double _size;

  @override
  void initState() {
    super.initState();
    _shape = widget.initialShape;
    _color = widget.initialColor;
    _size = widget.initialSize;
  }

  @override
  Widget build(BuildContext context) {
    return ObjectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Значок и цвет', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: widget.previewBuilder?.call(_shape, _color, _size) ??
                DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      _icon(_shape),
                      size: _size,
                      color: _parseColor(_color),
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            children: _shapes
                .map(
                  (shape) => IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: shape == _shape
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2)
                          : null,
                    ),
                    onPressed: () => setState(() => _shape = shape),
                    icon: Icon(_icon(shape)),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: _colors
                .map(
                  (color) => InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _parseColor(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _color
                              ? Colors.white
                              : Theme.of(context).dividerColor,
                          width: color == _color ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          Text('Размер: ${_size.round()}'),
          Slider(
            value: _size.clamp(24, 48),
            min: 24,
            max: 48,
            divisions: 24,
            onChanged: (value) => setState(() => _size = value),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                MarkerStyleSelection(
                  shape: _shape,
                  colorHex: _color,
                  size: _size,
                ),
              ),
              child: const Text('Готово'),
            ),
          ),
        ],
      ),
    );
  }

  static Color _parseColor(String value) =>
      Color(int.parse(value.replaceFirst('#', '0xFF')));

  static IconData _icon(String shape) => switch (shape) {
        'star' => Icons.star,
        'flag' => Icons.flag,
        'home' => Icons.home,
        'work' => Icons.work,
        'circle' => Icons.circle,
        'square' => Icons.square,
        'triangle' => Icons.change_history,
        _ => Icons.location_on,
      };
}
