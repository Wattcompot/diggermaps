import 'package:flutter/material.dart';

import '../../../data/models/user_marker.dart';
import '../object_bottom_sheet.dart';

class MarkerBottomSheet extends StatefulWidget {
  const MarkerBottomSheet({
    super.key,
    required this.marker,
    required this.onDelete,
    required this.onStyle,
    required this.onShare,
    required this.onExport,
    required this.onCopyCoordinates,
    required this.onNavigation,
    required this.onDirection,
  });

  final UserMarker marker;
  final Future<bool> Function(UserMarker marker) onDelete;
  final Future<UserMarker?> Function(UserMarker marker) onStyle;
  final VoidCallback onShare;
  final VoidCallback onExport;
  final VoidCallback onCopyCoordinates;
  final VoidCallback onNavigation;
  final VoidCallback onDirection;

  static Future<UserMarker?> show(
    BuildContext context, {
    required UserMarker marker,
    required Future<bool> Function(UserMarker marker) onDelete,
    required Future<UserMarker?> Function(UserMarker marker) onStyle,
    required VoidCallback onShare,
    required VoidCallback onExport,
    required VoidCallback onCopyCoordinates,
    required VoidCallback onNavigation,
    required VoidCallback onDirection,
  }) {
    return showModalBottomSheet<UserMarker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MarkerBottomSheet(
        marker: marker,
        onDelete: onDelete,
        onStyle: onStyle,
        onShare: onShare,
        onExport: onExport,
        onCopyCoordinates: onCopyCoordinates,
        onNavigation: onNavigation,
        onDirection: onDirection,
      ),
    );
  }

  @override
  State<MarkerBottomSheet> createState() => _MarkerBottomSheetState();
}

class _MarkerBottomSheetState extends State<MarkerBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late UserMarker _marker;

  @override
  void initState() {
    super.initState();
    _marker = widget.marker;
    _nameController = TextEditingController(text: _marker.name);
    _descriptionController =
        TextEditingController(text: _marker.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  UserMarker get _result => _marker.copyWith(
        name: _nameController.text.trim().isEmpty
            ? _marker.name
            : _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    return ObjectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  final updated = await widget.onStyle(_result);
                  if (updated != null && mounted) {
                    setState(() => _marker = updated);
                  }
                },
                child: CircleAvatar(
                  child: Icon(
                    Icons.location_on,
                    color: Color(
                      int.parse(_marker.colorHex.replaceFirst('#', '0xFF')),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _descriptionController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Описание',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Размер метки'),
          ),
          SegmentedButton<double>(
            segments: const <ButtonSegment<double>>[
              ButtonSegment<double>(value: 24, label: Text('Маленький')),
              ButtonSegment<double>(value: 32, label: Text('Средний')),
              ButtonSegment<double>(value: 48, label: Text('Большой')),
            ],
            selected: <double>{_closestSize(_marker.size)},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(
              () => _marker = _marker.copyWith(size: selection.first),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Видимость на карте'),
            value: _marker.visible,
            onChanged: (value) =>
                setState(() => _marker = _marker.copyWith(visible: value)),
          ),
          _action(Icons.share, 'Поделиться', widget.onShare),
          _action(Icons.delete, 'Удалить', () async {
            if (await widget.onDelete(_result) && context.mounted) {
              Navigator.pop(context);
            }
          }, color: Colors.red),
          _action(Icons.save_alt, 'Экспорт', widget.onExport),
          _action(Icons.content_copy, 'Копировать координаты',
              widget.onCopyCoordinates),
          _action(Icons.navigation, 'Навигация к точке', widget.onNavigation),
          _action(Icons.explore, 'Направление к метке', widget.onDirection),
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
  }

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

  static double _closestSize(double size) {
    if (size < 28) return 24;
    if (size < 40) return 32;
    return 48;
  }
}
