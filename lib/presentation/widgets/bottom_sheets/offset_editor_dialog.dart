import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/custom_map_repository.dart';

class OffsetEditorDialog extends StatefulWidget {
  const OffsetEditorDialog({
    super.key,
    required this.map,
    required this.onSave,
  });

  final CustomMapLayer map;
  final FutureOr<void> Function(double lat, double lng) onSave;

  static Future<void> show(
    BuildContext context, {
    required CustomMapLayer map,
    required FutureOr<void> Function(double lat, double lng) onSave,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => OffsetEditorDialog(map: map, onSave: onSave),
    );
  }

  @override
  State<OffsetEditorDialog> createState() => _OffsetEditorDialogState();
}

class _OffsetEditorDialogState extends State<OffsetEditorDialog> {
  late double _latOffset;
  late double _lngOffset;

  @override
  void initState() {
    super.initState();
    _latOffset = widget.map.latitudeOffset;
    _lngOffset = widget.map.longitudeOffset;
  }

  Future<void> _save() async {
    await widget.onSave(_latOffset, _lngOffset);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Смещение: ${widget.map.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Широта: ${_latOffset.toStringAsFixed(6)}'),
          Slider(
            value: _latOffset,
            min: -0.01,
            max: 0.01,
            onChanged: (value) => setState(() => _latOffset = value),
          ),
          Text('Долгота: ${_lngOffset.toStringAsFixed(6)}'),
          Slider(
            value: _lngOffset,
            min: -0.01,
            max: 0.01,
            onChanged: (value) => setState(() => _lngOffset = value),
          ),
          const Text(
            'Смещение применяется к тайлам выбранного слоя и сохраняется для карты.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
