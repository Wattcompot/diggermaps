import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class MarkerCreateSelection {
  const MarkerCreateSelection({
    required this.name,
    required this.description,
    required this.group,
    required this.colorHex,
    required this.shape,
    required this.size,
  });

  final String name;
  final String description;
  final String group;
  final String colorHex;
  final String shape;
  final double size;
}

class MarkerCreateDialog extends StatefulWidget {
  const MarkerCreateDialog({
    super.key,
    required this.point,
    required this.previewBuilder,
  });

  static const _speechChannel = MethodChannel('digger_maps/speech');

  final LatLng point;
  final Widget Function(String shape, String colorHex, double size)
      previewBuilder;

  static Future<MarkerCreateSelection?> show(
    BuildContext context, {
    required LatLng point,
    required Widget Function(String shape, String colorHex, double size)
        previewBuilder,
  }) {
    return showDialog<MarkerCreateSelection>(
      context: context,
      builder: (_) => MarkerCreateDialog(
        point: point,
        previewBuilder: previewBuilder,
      ),
    );
  }

  @override
  State<MarkerCreateDialog> createState() => _MarkerCreateDialogState();
}

class _MarkerCreateDialogState extends State<MarkerCreateDialog> {
  static const _colors = <String>[
    '#FF0000',
    '#A67B5B',
    '#00FF00',
    '#0000FF',
    '#FFFF00',
    '#FF00FF',
    '#00FFFF',
    '#000000',
    '#FFFFFF',
  ];
  static const _shapes = <(String, IconData)>[
    ('square', Icons.square_outlined),
    ('triangle', Icons.change_history),
    ('circle', Icons.circle_outlined),
    ('pin', Icons.location_pin),
    ('star', Icons.more_horiz),
  ];

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _groupController = TextEditingController(text: 'Общее');
  String _selectedColor = '#FF0000';
  String _selectedShape = 'pin';
  double _selectedSize = 42;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _groupController.dispose();
    super.dispose();
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

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }
    final group = _groupController.text.trim();
    Navigator.pop(
      context,
      MarkerCreateSelection(
        name: name,
        description: _descriptionController.text.trim(),
        group: group.isEmpty ? 'Общее' : group,
        colorHex: _selectedColor,
        shape: _selectedShape,
        size: _selectedSize,
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
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Форма метки'),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _shapes.map((item) {
                    final selected = _selectedShape == item.$1;
                    return InkWell(
                      onTap: () => setState(() => _selectedShape = item.$1),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFA67B5B)
                                : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.$2),
                      ),
                    );
                  }).toList(growable: false),
                ),
                Slider(
                  value: _selectedSize,
                  min: 24,
                  max: 72,
                  label: 'Размер ${_selectedSize.round()}',
                  activeColor: const Color(0xFFA67B5B),
                  thumbColor: const Color(0xFFA67B5B),
                  onChanged: (value) => setState(() => _selectedSize = value),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Цвет метки'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colors.map((color) {
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse(color.replaceFirst('#', '0xFF')),
                          ),
                          border: Border.all(
                            color: _selectedColor == color
                                ? const Color(0xFFA67B5B)
                                : Colors.grey,
                            width: 2,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
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
