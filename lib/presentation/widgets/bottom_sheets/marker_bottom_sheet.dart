import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/marker_media.dart';
import '../../../data/models/user_marker.dart';
import '../../../services/media/marker_media_service.dart';
import '../media/marker_media_section.dart';
import '../object_bottom_sheet.dart';
import '../poi/marker_appearance_button.dart';

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
    this.mediaService,
  });

  final UserMarker marker;
  final Future<bool> Function(UserMarker marker) onDelete;
  final Future<UserMarker?> Function(UserMarker marker) onStyle;
  final VoidCallback onShare;
  final VoidCallback onExport;
  final VoidCallback onCopyCoordinates;
  final VoidCallback onNavigation;
  final VoidCallback onDirection;

  /// Optional injection point (tests, or a host that shares one service).
  final MarkerMediaService? mediaService;

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
    MarkerMediaService? mediaService,
  }) {
    return showObjectBottomSheet<UserMarker>(
      context: context,
      builder: (_) => MarkerBottomSheet(
        marker: marker,
        onDelete: onDelete,
        onStyle: onStyle,
        onShare: onShare,
        onExport: onExport,
        onCopyCoordinates: onCopyCoordinates,
        onNavigation: onNavigation,
        onDirection: onDirection,
        mediaService: mediaService,
      ),
    );
  }

  @override
  State<MarkerBottomSheet> createState() => _MarkerBottomSheetState();
}

class _MarkerBottomSheetState extends State<MarkerBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final MarkerMediaService _mediaService;
  late final bool _ownsMediaService;
  late final Set<String> _originalRefs;
  final Set<String> _sessionRefs = <String>{};
  late UserMarker _marker;

  /// Set only when the editor result is returned to the caller: the new files
  /// are referenced by the saved marker from that moment on.
  bool _committed = false;
  bool _saving = false;
  final _mediaKey = GlobalKey<MarkerMediaSectionState>();

  @override
  void initState() {
    super.initState();
    _marker = widget.marker;
    _originalRefs = widget.marker.media.map((item) => item.fileRef).toSet();
    _mediaService = widget.mediaService ?? MarkerMediaService();
    _ownsMediaService = widget.mediaService == null;
    _nameController = TextEditingController(text: _marker.name);
    _descriptionController =
        TextEditingController(text: _marker.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    if (!_committed) {
      // Cancelled edit: remove the files this session created. Saved
      // attachments and the user's originals are never touched.
      unawaited(_discardDrafts());
    }
    if (_ownsMediaService) unawaited(_mediaService.dispose());
    super.dispose();
  }

  Future<void> _discardDrafts() async {
    try {
      await _mediaService.store.discardDrafts(
        originalRefs: _originalRefs,
        currentRefs: <String>{
          ..._sessionRefs,
          ..._marker.media.map((item) => item.fileRef),
        },
      );
    } catch (_) {
      // Cleanup is best effort: a locked file can be removed later.
    }
  }

  UserMarker get _result => _marker.copyWith(
        name: _nameController.text.trim().isEmpty
            ? _marker.name
            : _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );

  void _handleMediaChanged(List<MarkerMedia> media) {
    setState(() => _marker = _marker.copyWith(media: media));
  }

  Future<void> _commit() async {
    if (_saving) return;
    _saving = true;
    final ready = await _mediaKey.currentState?.prepareToSave() ?? true;
    _saving = false;
    if (!mounted || !ready) return;
    _committed = true;
    Navigator.pop(context, _result);
  }

  @override
  Widget build(BuildContext context) {
    return ObjectBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            decoration:
                const InputDecoration(labelText: 'Название', isDense: true),
          ),
          const SizedBox(height: 12),
          MarkerMediaSection(
            key: _mediaKey,
            descriptionController: _descriptionController,
            media: _marker.media,
            service: _mediaService,
            onChanged: _handleMediaChanged,
            onDraftCreated: _sessionRefs.add,
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            MarkerAppearanceButton(
                shape: _marker.shape,
                colorHex: _marker.colorHex,
                size: _marker.size,
                onTap: _editAppearance),
            const SizedBox(width: 12),
            Expanded(
                child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Внешний вид'),
              subtitle: const Text('Форма, цвет и размер'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editAppearance,
            )),
          ]),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Видимость на карте'),
            value: _marker.visible,
            onChanged: (value) =>
                setState(() => _marker = _marker.copyWith(visible: value)),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          _action(Icons.share, 'Поделиться', widget.onShare),
          _action(Icons.delete, 'Удалить', () async {
            // The marker (and therefore its attachments, including the drafts
            // of this session) disappears with it.
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
              onPressed: _commit,
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

  Future<void> _editAppearance() async {
    final updated = await widget.onStyle(_result);
    if (updated != null && mounted) setState(() => _marker = updated);
  }
}
