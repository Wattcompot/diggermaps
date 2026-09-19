import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/marker_media.dart';
import '../../../services/media/marker_media_service.dart';
import '../media/marker_media_section.dart';
import '../poi/marker_appearance_button.dart';
import 'marker_style_picker_sheet.dart';

class MarkerCreateSelection {
  const MarkerCreateSelection({
    required this.name,
    required this.description,
    required this.group,
    required this.colorHex,
    required this.shape,
    required this.size,
    this.media = const <MarkerMedia>[],
  });

  final String name;
  final String description;
  final String group;
  final String colorHex;
  final String shape;
  final double size;

  /// Вложения, добавленные прямо при создании метки.
  ///
  /// Это ссылки на файлы в папке приложения; вызывающий код переносит их в
  /// `UserMarker.media` (см. интеграционный сниппет для `map_screen.dart`).
  final List<MarkerMedia> media;
}

class MarkerCreateDialog extends StatefulWidget {
  const MarkerCreateDialog({
    super.key,
    required this.point,
    required this.previewBuilder,
    this.mediaService,
  });

  static const _speechChannel = MethodChannel('digger_maps/speech');

  final LatLng point;
  final Widget Function(String shape, String colorHex, double size)
      previewBuilder;

  /// Точка внедрения (тесты или общий сервис у вызывающего экрана).
  final MarkerMediaService? mediaService;

  static Future<MarkerCreateSelection?> show(
    BuildContext context, {
    required LatLng point,
    required Widget Function(String shape, String colorHex, double size)
        previewBuilder,
    MarkerMediaService? mediaService,
  }) {
    return showDialog<MarkerCreateSelection>(
      context: context,
      builder: (_) => MarkerCreateDialog(
        point: point,
        previewBuilder: previewBuilder,
        mediaService: mediaService,
      ),
    );
  }

  @override
  State<MarkerCreateDialog> createState() => _MarkerCreateDialogState();
}

class _MarkerCreateDialogState extends State<MarkerCreateDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _groupController = TextEditingController(text: 'Общее');
  String _selectedColor = '#FF0000';
  String _selectedShape = 'pin';
  double _selectedSize = 42;
  String? _nameError;

  late final MarkerMediaService _mediaService;
  late final bool _ownsMediaService;
  final Set<String> _sessionRefs = <String>{};
  List<MarkerMedia> _media = const <MarkerMedia>[];

  /// true только когда метка создана: с этого момента файлы принадлежат ей.
  bool _committed = false;
  bool _saving = false;
  final _mediaKey = GlobalKey<MarkerMediaSectionState>();

  @override
  void initState() {
    super.initState();
    _mediaService = widget.mediaService ?? MarkerMediaService();
    _ownsMediaService = widget.mediaService == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _groupController.dispose();
    if (!_committed) {
      // Диалог закрыт без создания метки: удаляем только файлы этой сессии.
      unawaited(_discardDrafts());
    }
    if (_ownsMediaService) unawaited(_mediaService.dispose());
    super.dispose();
  }

  Future<void> _discardDrafts() async {
    try {
      await _mediaService.store.discardDrafts(
        originalRefs: const <String>{},
        currentRefs: <String>{
          ..._sessionRefs,
          ..._media.map((item) => item.fileRef),
        },
      );
    } catch (_) {
      // Уборка черновиков не должна ломать закрытие диалога.
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _copyCoordinates() async {
    await Clipboard.setData(
      ClipboardData(
        text: '${widget.point.latitude}, ${widget.point.longitude}',
      ),
    );
    if (mounted) _showMessage('Координаты скопированы');
  }

  Future<void> _recognizeName() async {
    try {
      final value = await MarkerCreateDialog._speechChannel
          .invokeMethod<String>('recognize');
      if (!mounted || value == null || value.trim().isEmpty) return;
      setState(() {
        _nameController.text = value.trim();
        _nameError = null;
      });
    } on PlatformException {
      if (mounted) _showMessage('Голосовой ввод недоступен');
    } on MissingPluginException {
      if (mounted) {
        _showMessage(
          'Используйте микрофонную клавишу экранной клавиатуры',
        );
      }
    }
  }

  Future<void> _editAppearance() async {
    final style = await MarkerStylePickerSheet.show(context,
        point: widget.point,
        initialShape: _selectedShape,
        initialColor: _selectedColor,
        initialSize: _selectedSize,
        previewBuilder: widget.previewBuilder);
    if (!mounted || style == null) return;
    setState(() {
      _selectedShape = style.shape;
      _selectedColor = style.colorHex;
      _selectedSize = style.size;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }
    if (_saving) return;
    _saving = true;
    final ready = await _mediaKey.currentState?.prepareToSave() ?? true;
    _saving = false;
    if (!mounted || !ready) return;
    final group = _groupController.text.trim();
    _committed = true;
    Navigator.pop(
      context,
      MarkerCreateSelection(
        name: name,
        description: _descriptionController.text.trim(),
        group: group.isEmpty ? 'Общее' : group,
        colorHex: _selectedColor,
        shape: _selectedShape,
        size: _selectedSize,
        media: List<MarkerMedia>.unmodifiable(_media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      contentPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Новая метка'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                widget.previewBuilder(
                  _selectedShape,
                  _selectedColor,
                  _selectedSize,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${widget.point.latitude.toStringAsFixed(6)}, '
                        '${widget.point.longitude.toStringAsFixed(6)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Копировать координаты',
                      icon: const Icon(Icons.content_copy),
                      onPressed: _copyCoordinates,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Название',
                    errorText: _nameError,
                    suffixIcon: IconButton(
                      tooltip: 'Голосовой ввод',
                      icon: const Icon(Icons.mic),
                      onPressed: _recognizeName,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MarkerMediaSection(
                  key: _mediaKey,
                  descriptionController: _descriptionController,
                  media: _media,
                  service: _mediaService,
                  onChanged: (media) => setState(() => _media = media),
                  onDraftCreated: _sessionRefs.add,
                ),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  MarkerAppearanceButton(
                      shape: _selectedShape,
                      colorHex: _selectedColor,
                      onTap: _editAppearance),
                  const SizedBox(width: 12),
                  Expanded(
                      child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Внешний вид'),
                          subtitle: const Text('Форма, цвет и размер'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _editAppearance)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _groupController,
                  decoration: const InputDecoration(labelText: 'Группа'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA67B5B),
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
