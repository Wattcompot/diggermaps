import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/drawing.dart';
import '../object_bottom_sheet.dart';

class DrawingBottomSheet extends StatefulWidget {
  const DrawingBottomSheet({
    super.key,
    required this.drawing,
    required this.typeLabel,
    required this.valueLabel,
    required this.onDelete,
    required this.onShare,
    required this.onCopyCoordinates,
    required this.onNavigation,
  });

  final Drawing drawing;
  final String typeLabel;
  final String valueLabel;
  final Future<bool> Function(Drawing drawing) onDelete;
  final VoidCallback onShare;
  final VoidCallback onCopyCoordinates;
  final VoidCallback onNavigation;

  static Future<Drawing?> show(
    BuildContext context, {
    required Drawing drawing,
    required String typeLabel,
    required String valueLabel,
    required Future<bool> Function(Drawing drawing) onDelete,
    required VoidCallback onShare,
    required VoidCallback onCopyCoordinates,
    required VoidCallback onNavigation,
  }) =>
      showModalBottomSheet<Drawing>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DrawingBottomSheet(
          drawing: drawing,
          typeLabel: typeLabel,
          valueLabel: valueLabel,
          onDelete: onDelete,
          onShare: onShare,
          onCopyCoordinates: onCopyCoordinates,
          onNavigation: onNavigation,
        ),
      );

  @override
  State<DrawingBottomSheet> createState() => _DrawingBottomSheetState();
}

class _DrawingBottomSheetState extends State<DrawingBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Drawing _drawing;

  @override
  void initState() {
    super.initState();
    _drawing = widget.drawing;
    _nameController = TextEditingController(text: _drawing.name);
    _descriptionController =
        TextEditingController(text: _drawing.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Drawing get _result => _drawing.copyWith(
        name: _nameController.text.trim().isEmpty
            ? _drawing.name
            : _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

  @override
  Widget build(BuildContext context) => ObjectBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ObjectEditorFields(
              nameController: _nameController,
              descriptionController: _descriptionController,
              leading: Icon(Icons.draw, color: Color(_drawing.color)),
              colors: objectEditorColors,
              selectedColor: Color(_drawing.color),
              onColorSelected: (color) => setState(
                () => _drawing = _drawing.copyWith(color: color.toARGB32()),
              ),
              visible: _drawing.visible,
              onVisibilityChanged: (value) => setState(
                () => _drawing = _drawing.copyWith(visible: value),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.straighten),
              title: Text(widget.typeLabel),
              subtitle: Text(widget.valueLabel),
            ),
            _action(Icons.delete, 'Удалить', () async {
              if (await widget.onDelete(_result) && context.mounted) {
                Navigator.pop(context);
              }
            }, color: Colors.red),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Создано'),
              subtitle: Text(
                DateFormat('dd.MM.yyyy, HH:mm')
                    .format(_drawing.createdAt.toLocal()),
              ),
            ),
            _action(Icons.share, 'Поделиться', widget.onShare),
            _action(Icons.content_copy, 'Копировать координаты',
                widget.onCopyCoordinates),
            _action(
                Icons.navigation, 'Навигация к объекту', widget.onNavigation),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _result),
                child: const Text('Готово'),
              ),
            ),
          ],
        ),
      );

  Widget _action(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        onTap: onTap,
      );
}
