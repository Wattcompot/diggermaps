import 'package:flutter/material.dart';

import '../../data/models/imported_map.dart';
import '../../data/repositories/imported_map_repository.dart';
import '../../theme/app_theme.dart';

/// Экран «Мои карты»: импортированные карты и каталог.
class MyMapsScreen extends StatefulWidget {
  const MyMapsScreen({
    this.onImport,
    super.key,
  });

  final Future<void> Function()? onImport;

  @override
  State<MyMapsScreen> createState() => _MyMapsScreenState();
}

class _MyMapsScreenState extends State<MyMapsScreen> {
  final ImportedMapRepository _repository = ImportedMapRepository();
  final TextEditingController _searchController = TextEditingController();

  List<ImportedMap> _maps = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadMaps();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _query = _searchController.text.trim().toLowerCase());
  }

  Future<void> _loadMaps() async {
    try {
      final maps = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _maps = maps;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final maps = await _repository.getAll();
      if (!mounted) return;
      setState(() => _maps = maps);
    } catch (_) {
      // Игнорируем — список останется прежним.
    }
  }

  List<ImportedMap> get _filteredMaps {
    if (_query.isEmpty) return _maps;
    return _maps
        .where((map) => map.name.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  Future<void> _setVisibility(ImportedMap map, bool visible) async {
    final id = map.id;
    if (id == null) return;
    await _repository.updateVisibility(id, visible);
    if (!mounted) return;
    setState(() {
      final index = _maps.indexWhere((item) => item.id == id);
      if (index >= 0) _maps[index] = map.copyWith(visible: visible);
    });
  }

  Future<void> _renameMap(ImportedMap map) async {
    final id = map.id;
    if (id == null) return;
    final newName = await showRenameMapDialog(context, initialName: map.name);
    if (newName == null || newName.trim().isEmpty || newName == map.name) {
      return;
    }
    await _repository.updateName(id, newName.trim());
    if (!mounted) return;
    setState(() {
      final index = _maps.indexWhere((item) => item.id == id);
      if (index >= 0) _maps[index] = map.copyWith(name: newName.trim());
    });
  }

  Future<void> _deleteMap(ImportedMap map) async {
    final id = map.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карту?'),
        content: Text(
          '«${map.name}» будет удалена без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppThemeTokens.of(context).dangerColor,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(id);
    if (!mounted) return;
    setState(() {
      _maps = _maps.where((item) => item.id != id).toList(growable: false);
    });
  }

  void _startCalibrationOnMap(ImportedMap map) {
    final id = map.id;
    if (id == null || !map.isRasterOverlay) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _openImport() async {
    final onImport = widget.onImport;
    if (onImport == null) return;
    await onImport();
    if (!mounted) return;
    await _loadMaps();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = AppThemeTokens.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мои карты'),
          backgroundColor: isDark
              ? Theme.of(context).colorScheme.surface
              : tokens.primaryAccent,
          foregroundColor: isDark
              ? tokens.onSurfaceIcon
              : Theme.of(context).colorScheme.onPrimary,
          actions: [
            if (widget.onImport != null)
              IconButton(
                tooltip: 'Импортировать карту',
                onPressed: _openImport,
                icon: const Icon(Icons.add),
              ),
          ],
          bottom: TabBar(
            indicatorColor: isDark
                ? tokens.primaryAccent
                : Theme.of(context).colorScheme.onPrimary,
            labelColor: isDark
                ? tokens.primaryAccent
                : Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: isDark
                ? tokens.onSurfaceMuted
                : Theme.of(context)
                    .colorScheme
                    .onPrimary
                    .withValues(alpha: 0.7),
            tabs: const [
              Tab(icon: Icon(Icons.store), text: 'Каталог'),
              Tab(icon: Icon(Icons.folder), text: 'Импортированные'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  const _CatalogTab(),
                  _buildImportedTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildImportedTab() {
    final items = _filteredMaps;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Поиск по названию',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _maps.isEmpty
                        ? 'Нет импортированных карт'
                        : 'Ничего не найдено',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final map = items[index];
                      return _ImportedMapCard(
                        map: map,
                        onVisibilityChanged: (value) =>
                            _setVisibility(map, value),
                        onCalibrate: () => _startCalibrationOnMap(map),
                        onRename: () => _renameMap(map),
                        onDelete: () => _deleteMap(map),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Диалог переименования карты. Возвращает новое имя или null при отмене.
Future<String?> showRenameMapDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameMapDialog(initialName: initialName),
  );
}

class _RenameMapDialog extends StatefulWidget {
  const _RenameMapDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameMapDialog> createState() => _RenameMapDialogState();
}

class _RenameMapDialogState extends State<_RenameMapDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Переименовать'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Название карты'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppThemeTokens.of(context).primaryAccent,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ImportedMapCard extends StatelessWidget {
  const _ImportedMapCard({
    required this.map,
    required this.onVisibilityChanged,
    required this.onCalibrate,
    required this.onRename,
    required this.onDelete,
  });

  final ImportedMap map;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onCalibrate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = AppThemeTokens.of(context);
    final textColor = theme.textTheme.bodyMedium?.color;
    final iconColor = tokens.onSurfaceIcon;
    final panelColor = tokens.cardBackground;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onRename,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      map.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.primaryAccent.withValues(
                        alpha: isDark ? 0.35 : 0.15,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      map.format.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.primaryAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.visibility, size: 18, color: iconColor),
                  const SizedBox(width: 6),
                  Text('На карте', style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Switch(
                    value: map.visible,
                    activeThumbColor: tokens.primaryAccent,
                    activeTrackColor:
                        tokens.primaryAccent.withValues(alpha: 0.5),
                    onChanged: onVisibilityChanged,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _ActionIconButton(
                    icon: Icons.open_with,
                    tooltip: 'Калибровка',
                    onPressed: onCalibrate,
                  ),
                  _ActionIconButton(
                    icon: Icons.edit,
                    tooltip: 'Переименовать',
                    onPressed: onRename,
                  ),
                  _ActionIconButton(
                    icon: Icons.delete,
                    tooltip: 'Удалить',
                    color: tokens.dangerColor,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppThemeTokens.of(context).onSurfaceIcon;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: effectiveColor),
      onPressed: onPressed,
    );
  }
}

/// Заглушка каталога.
class _CatalogTab extends StatelessWidget {
  const _CatalogTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag,
            size: 56,
            color: tokens.onSurfaceMuted.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 16),
          Text(
            'Скоро',
            style: theme.textTheme.titleMedium?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
