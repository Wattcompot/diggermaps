import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/track.dart';
import '../object_bottom_sheet.dart';

class TrackSaveSelection {
  const TrackSaveSelection({required this.name, required this.color});

  final String name;
  final int color;
}

class TrackBottomSheet extends StatefulWidget {
  const TrackBottomSheet({
    super.key,
    required this.track,
    required this.onDelete,
    required this.onHistory,
    required this.onShare,
    required this.onNavigation,
  });

  final Track track;
  final Future<bool> Function(Track track) onDelete;
  final VoidCallback onHistory;
  final VoidCallback onShare;
  final VoidCallback onNavigation;

  static Future<Track?> show(
    BuildContext context, {
    required Track track,
    required Future<bool> Function(Track track) onDelete,
    required VoidCallback onHistory,
    required VoidCallback onShare,
    required VoidCallback onNavigation,
  }) =>
      showModalBottomSheet<Track>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TrackBottomSheet(
          track: track,
          onDelete: onDelete,
          onHistory: onHistory,
          onShare: onShare,
          onNavigation: onNavigation,
        ),
      );

  static Future<TrackSaveSelection?> showSave(
    BuildContext context, {
    required String defaultName,
  }) =>
      showDialog<TrackSaveSelection>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TrackSaveDialog(defaultName: defaultName),
      );

  @override
  State<TrackBottomSheet> createState() => _TrackBottomSheetState();
}

class _TrackBottomSheetState extends State<TrackBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Track _track;

  @override
  void initState() {
    super.initState();
    _track = widget.track;
    _nameController = TextEditingController(text: _track.name);
    _descriptionController =
        TextEditingController(text: _track.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Track get _result => _track.copyWith(
        name: _nameController.text.trim().isEmpty
            ? _track.name
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
              leading: Icon(Icons.route, color: Color(_track.color)),
              colors: objectEditorColors,
              selectedColor: Color(_track.color),
              onColorSelected: (color) => setState(
                () => _track = _track.copyWith(color: color.toARGB32()),
              ),
              visible: _track.visible,
              onVisibilityChanged: (value) =>
                  setState(() => _track = _track.copyWith(visible: value)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.straighten),
              title: Text('${(_track.distance / 1000).toStringAsFixed(2)} км'),
              subtitle: Text(
                'Средняя скорость '
                '${(_track.duration <= 0 ? 0 : _track.distance / _track.duration * 3.6).toStringAsFixed(1)} км/ч',
              ),
            ),
            _action(Icons.delete, 'Удалить', () async {
              if (await widget.onDelete(_result) && context.mounted) {
                Navigator.pop(context);
              }
            }, color: Colors.red),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Начало записи'),
              subtitle: Text(
                DateFormat('dd.MM.yyyy, HH:mm')
                    .format(_track.createdAt.toLocal()),
              ),
            ),
            _action(Icons.history, 'История', widget.onHistory),
            _action(Icons.share, 'Поделиться / экспорт GPX', widget.onShare),
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

class _TrackSaveDialog extends StatefulWidget {
  const _TrackSaveDialog({required this.defaultName});

  final String defaultName;

  @override
  State<_TrackSaveDialog> createState() => _TrackSaveDialogState();
}

class _TrackSaveDialogState extends State<_TrackSaveDialog> {
  late final TextEditingController _controller;
  Color _color = objectEditorColors.first;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Сохранить трек'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название',
                hintText: widget.defaultName,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Цвет трека'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: objectEditorColors
                  .map(
                    (color) => InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == _color ? Colors.white : Colors.grey,
                            width: color == _color ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отменить'),
          ),
          FilledButton(
            onPressed: () {
              final name = _controller.text.trim();
              Navigator.pop(
                context,
                TrackSaveSelection(
                  name: name.isEmpty ? widget.defaultName : name,
                  color: _color.toARGB32(),
                ),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
