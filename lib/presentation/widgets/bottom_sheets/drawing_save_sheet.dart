import 'package:flutter/material.dart';

class DrawingSaveSheet extends StatefulWidget {
  const DrawingSaveSheet({super.key, required this.defaultName});

  final String defaultName;

  static Future<String?> show(BuildContext context, String defaultName) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
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
                  onPressed: () {
                    final value = _controller.text.trim();
                    Navigator.pop(
                      context,
                      value.isEmpty ? widget.defaultName : value,
                    );
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
