import 'package:flutter/material.dart';

import '../object_bottom_sheet.dart';

/// Быстрый ввод имени перед сохранением рисунка/измерения.
/// Использует общий [ObjectBottomSheet], чтобы не дублировать scrollbar
/// и получить корректные ограничения высоты и учёт клавиатуры.
class DrawingSaveSheet extends StatefulWidget {
  const DrawingSaveSheet({super.key, required this.defaultName});

  final String defaultName;

  static Future<String?> show(BuildContext context, String defaultName) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DrawingSaveSheet(defaultName: defaultName),
    );
  }

  @override
  State<DrawingSaveSheet> createState() => _DrawingSaveSheetState();
}

class _DrawingSaveSheetState extends State<DrawingSaveSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.pop(context, value.isEmpty ? widget.defaultName : value);
  }

  @override
  Widget build(BuildContext context) {
    return ObjectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Сохранить объект',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Название',
              hintText: widget.defaultName,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
