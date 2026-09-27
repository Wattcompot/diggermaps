import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../object_bottom_sheet.dart';

/// Один файл, выбранный пользователем во встроенной галерее.
class DeviceGalleryPick {
  const DeviceGalleryPick({required this.path, required this.isVideo});

  final String path;
  final bool isVideo;
}

/// Уровень доступа к медиатеке устройства.
enum DeviceGalleryAccess { granted, limited, denied }

/// Один элемент медиатеки: миниатюра и путь к исходному файлу.
///
/// Абстракция нужна, чтобы экран галереи можно было проверить тестами без
/// платформенного плагина.
abstract class DeviceGalleryAsset {
  String get id;
  bool get isVideo;
  Duration? get duration;
  Future<Uint8List?> thumbnailData(int extent);
  Future<String?> resolvePath();
}

/// Источник элементов галереи.
abstract class DeviceGallerySource {
  /// Запрашивает доступ к фото и видео устройства.
  Future<DeviceGalleryAccess> ensureAccess();

  /// Отдаёт страницу элементов от новых к старым.
  Future<List<DeviceGalleryAsset>> loadPage({
    required int page,
    required int pageSize,
    required bool videoOnly,
  });

  /// Открывает системные настройки, если доступ запрещён.
  Future<void> openSettings();
}

/// Штатный источник на `photo_manager` (Android/iOS).
class PhotoManagerGallerySource implements DeviceGallerySource {
  PhotoManagerGallerySource();

  final Map<bool, AssetPathEntity?> _albums = <bool, AssetPathEntity?>{};

  @override
  Future<DeviceGalleryAccess> ensureAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return switch (state) {
      PermissionState.authorized => DeviceGalleryAccess.granted,
      PermissionState.limited => DeviceGalleryAccess.limited,
      _ => DeviceGalleryAccess.denied,
    };
  }

  @override
  Future<List<DeviceGalleryAsset>> loadPage({
    required int page,
    required int pageSize,
    required bool videoOnly,
  }) async {
    final album = _albums[videoOnly] ??= await _album(videoOnly);
    if (album == null) return const <DeviceGalleryAsset>[];
    final assets = await album.getAssetListPaged(page: page, size: pageSize);
    return assets
        .map<DeviceGalleryAsset>(PhotoManagerGalleryAsset.new)
        .toList(growable: false);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  Future<AssetPathEntity?> _album(bool videoOnly) async {
    // Источник порядка: сортируем сам альбом по дате создания убыванием, чтобы
    // `getAssetListPaged` отдавал новые элементы первыми (платформенный
    // порядок по умолчанию — от старых к новым). Порядок задаётся здесь,
    // одинаково для фото и видео.
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: videoOnly ? RequestType.video : RequestType.image,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    return paths.isEmpty ? null : paths.first;
  }
}

/// Обёртка над [AssetEntity] из `photo_manager`.
class PhotoManagerGalleryAsset implements DeviceGalleryAsset {
  PhotoManagerGalleryAsset(this.entity);

  final AssetEntity entity;

  @override
  String get id => entity.id;

  @override
  bool get isVideo => entity.type == AssetType.video;

  @override
  Duration? get duration {
    if (!isVideo) return null;
    final value = entity.videoDuration;
    return value == Duration.zero ? null : value;
  }

  @override
  Future<Uint8List?> thumbnailData(int extent) =>
      entity.thumbnailDataWithSize(ThumbnailSize.square(extent), quality: 85);

  @override
  Future<String?> resolvePath() async {
    final file = await entity.file;
    return file?.path;
  }
}

/// Встроенная галерея приложения: сетка фото и видео устройства.
///
/// Системный файловый менеджер и внешнее приложение галереи не открываются —
/// пользователь выбирает вложения прямо в DiggerMaps. Экран умеет:
///  * переключаться между фото и видео;
///  * выбирать несколько элементов сразу (до [maxSelection]);
///  * показывать длительность видео и явный значок воспроизведения;
///  * объяснять ситуацию, когда доступ к медиатеке запрещён.
class DeviceGallerySheet extends StatefulWidget {
  const DeviceGallerySheet({
    super.key,
    this.source,
    this.initialVideo = false,
    this.maxSelection = defaultMaxSelection,
  });

  /// Разумный предел: редактор остаётся компактным, а вложение — управляемым.
  static const int defaultMaxSelection = 10;

  /// Точка внедрения (тесты или общий источник у вызывающего экрана).
  final DeviceGallerySource? source;

  /// Открыть сразу на видео (когда пользователь нажал «Видео»).
  final bool initialVideo;
  final int maxSelection;

  static Future<List<DeviceGalleryPick>?> show(
    BuildContext context, {
    bool initialVideo = false,
    DeviceGallerySource? source,
    int maxSelection = defaultMaxSelection,
  }) =>
      showObjectBottomSheet<List<DeviceGalleryPick>>(
        context: context,
        builder: (_) => DeviceGallerySheet(
          source: source,
          initialVideo: initialVideo,
          maxSelection: maxSelection,
        ),
      );

  @override
  State<DeviceGallerySheet> createState() => _DeviceGallerySheetState();
}

class _DeviceGallerySheetState extends State<DeviceGallerySheet> {
  static const int _pageSize = 60;

  late final DeviceGallerySource _source =
      widget.source ?? PhotoManagerGallerySource();
  late final ScrollController _scroll = ScrollController();
  final Map<String, DeviceGalleryAsset> _selection =
      <String, DeviceGalleryAsset>{};
  final Map<String, Future<Uint8List?>> _thumbnails =
      <String, Future<Uint8List?>>{};

  late bool _videoOnly = widget.initialVideo;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  DeviceGalleryAccess? _access;
  List<DeviceGalleryAsset> _items = const <DeviceGalleryAsset>[];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _start();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 400) _loadMore();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final access = await _source.ensureAccess();
      if (!mounted) return;
      if (access == DeviceGalleryAccess.denied) {
        setState(() {
          _access = access;
          _loading = false;
          _items = const <DeviceGalleryAsset>[];
          _hasMore = false;
        });
        return;
      }
      _access = access;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _access = DeviceGalleryAccess.denied;
        _loading = false;
        _hasMore = false;
      });
      return;
    }
    await _loadPage(reset: true);
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loadingMore) return;
    if (!reset && !_hasMore) return;
    if (reset) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 0 : _page;
      final items = await _source.loadPage(
        page: page,
        pageSize: _pageSize,
        videoOnly: _videoOnly,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? items : <DeviceGalleryAsset>[..._items, ...items];
        _page = page + 1;
        _hasMore = items.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _loadMore() {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadPage(reset: false);
  }

  void _switchType(bool video) {
    if (_videoOnly == video) return;
    setState(() {
      _videoOnly = video;
      _items = const <DeviceGalleryAsset>[];
      _page = 0;
      _hasMore = true;
      _thumbnails.clear();
    });
    _scroll.jumpTo(0);
    _loadPage(reset: true);
  }

  void _toggle(DeviceGalleryAsset asset) {
    if (_selection.containsKey(asset.id)) {
      setState(() => _selection.remove(asset.id));
      return;
    }
    if (_selection.length >= widget.maxSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Можно добавить не больше ${widget.maxSelection} вложений за раз',
          ),
        ),
      );
      return;
    }
    setState(() => _selection[asset.id] = asset);
  }

  Future<void> _confirm() async {
    final selected = _selection.values.toList(growable: false);
    if (selected.isEmpty) return;
    final picks = <DeviceGalleryPick>[];
    for (final asset in selected) {
      final path = await asset.resolvePath();
      if (path == null || path.isEmpty) continue;
      picks.add(DeviceGalleryPick(path: path, isVideo: asset.isVideo));
    }
    if (!mounted) return;
    if (picks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть выбранные файлы')),
      );
      return;
    }
    Navigator.of(context).pop(picks);
  }

  Future<Uint8List?> _thumbnail(DeviceGalleryAsset asset) =>
      _thumbnails.putIfAbsent(asset.id, () => asset.thumbnailData(240));

  /// Крупный предпросмотр выбранного элемента.
  ///
  /// Для фото — во весь экран с масштабированием; для видео — увеличенный кадр
  /// с длительностью и кнопкой воспроизведения.
  Future<void> _preview(DeviceGalleryAsset asset) async {
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width,
            maxHeight: size.height * 0.86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black,
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: _PreviewSurface(asset: asset),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      asset.isVideo ? 'Видео' : 'Фотография',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    final selected = _selection.values.toList(growable: false);
    return ObjectBottomSheet(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: <Widget>[
                  Text('Галерея', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  ChoiceChip(
                    label: const Text('Фото'),
                    selected: !_videoOnly,
                    showCheckmark: false,
                    onSelected: (_) => _switchType(false),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Видео'),
                    selected: _videoOnly,
                    showCheckmark: false,
                    onSelected: (_) => _switchType(true),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme)),
            if (selected.isNotEmpty) _buildSelectionStrip(theme, selected),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _selection.isEmpty
                          ? 'Ничего не выбрано'
                          : 'Выбрано: ${_selection.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: _selection.isEmpty ? null : _confirm,
                    child: const Text('Добавить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Полоса выбранных вложений: видно, что именно уйдёт в метку.
  ///
  /// Пока ничего не выбрано, полосы нет — сетка остаётся максимально большой.
  Widget _buildSelectionStrip(
    ThemeData theme,
    List<DeviceGalleryAsset> selected,
  ) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: selected.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final asset = selected[index];
          return GestureDetector(
            key: ValueKey<String>('gallery-selected-${asset.id}'),
            onTap: () => _preview(asset),
            child: Stack(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: _Thumbnail(asset: asset, future: _thumbnail(asset)),
                  ),
                ),
                if (asset.isVideo)
                  const Positioned(
                    left: 3,
                    bottom: 3,
                    child:
                        Icon(Icons.play_arrow, size: 14, color: Colors.white),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _toggle(asset),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_access == DeviceGalleryAccess.denied) return _buildDenied(theme);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _videoOnly ? 'На устройстве нет видео' : 'На устройстве нет фото',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _items.length + (_loadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const ColoredBox(
            color: Colors.black12,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildTile(theme, _items[index]);
      },
    );
  }

  Widget _buildDenied(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.photo_library_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'Нет доступа к галерее устройства',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Разрешите доступ к фото и видео в настройках, чтобы '
                'прикреплять их к метке.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _source.openSettings(),
                child: const Text('Открыть настройки'),
              ),
            ],
          ),
        ),
      );

  Widget _buildTile(ThemeData theme, DeviceGalleryAsset asset) {
    final index = _selection.keys.toList(growable: false).indexOf(asset.id);
    final selected = index >= 0;
    return GestureDetector(
      key: ValueKey<String>('gallery-tile-${asset.id}'),
      onTap: () => _toggle(asset),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _Thumbnail(asset: asset, future: _thumbnail(asset)),
          ),
          // Явный признак видео: иконка воспроизведения и длительность.
          if (asset.isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.play_arrow,
                          size: 12, color: Colors.white),
                      if (asset.duration case final duration?) ...<Widget>[
                        const SizedBox(width: 2),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: SizedBox.square(
              dimension: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.black.withValues(alpha: 0.35),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          // Предпросмотр, не меняя выбор: увеличить фото или посмотреть кадр
          // видео можно до добавления в метку.
          Positioned(
            left: 4,
            top: 4,
            child: GestureDetector(
              key: ValueKey<String>('gallery-preview-${asset.id}'),
              onTap: () => _preview(asset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child:
                      Icon(Icons.zoom_out_map, size: 13, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// Миниатюра элемента галереи с запасной иконкой вместо пустого места.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.asset, required this.future});

  final DeviceGalleryAsset asset;
  final Future<Uint8List?> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              asset.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined, size: 22),
          ),
        );
      },
    );
  }
}

/// Крупное превью элемента: для фото — полный кадр с масштабированием, для
/// видео — кадр с кнопкой Play, а по нажатию — реальное воспроизведение прямо
/// в превью (без автозапуска; повторный тап ставит на паузу/возобновляет).
class _PreviewSurface extends StatefulWidget {
  const _PreviewSurface({required this.asset});

  final DeviceGalleryAsset asset;

  @override
  State<_PreviewSurface> createState() => _PreviewSurfaceState();
}

class _PreviewSurfaceState extends State<_PreviewSurface> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  /// Единая точка Play/Pause. Первый вызов лениво создаёт плеер и запускает
  /// его — воспроизведение стартует только по явному нажатию, автозапуска нет.
  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        // После конца ролика — снова с начала.
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
      return;
    }
    if (_initializing) return;
    setState(() {
      _initializing = true;
      _failed = false;
    });
    try {
      final path = await widget.asset.resolvePath();
      if (path == null || path.isEmpty) {
        throw StateError('Файл недоступен');
      }
      final created = VideoPlayerController.file(File(path));
      await created.initialize();
      if (!mounted) {
        await created.dispose();
        return;
      }
      created.addListener(_onTick);
      setState(() {
        _controller = created;
        _initializing = false;
      });
      await created.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.asset.isVideo) return _photo();
    return _video();
  }

  /// Фото: полный кадр с зумом (масштабирование сохраняется как прежде).
  Widget _photo() => FutureBuilder<Uint8List?>(
        future: widget.asset.thumbnailData(1080),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(
              child:
                  Icon(Icons.image_outlined, size: 48, color: Colors.white54),
            );
          }
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        },
      );

  Widget _video() {
    final controller = _controller;
    final playing = controller?.value.isPlaying ?? false;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (controller != null && controller.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 3 / 4
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          )
        else
          _videoFrame(),
        // Кадр видео/плеер целиком реагирует на тап как Play/Pause.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _initializing ? null : _togglePlayback,
          ),
        ),
        if (_initializing)
          const Center(
            child: SizedBox.square(
              dimension: 42,
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (!playing)
          // Пауза/старт: явная кнопка Play (после остановки можно запустить
          // снова). Во время воспроизведения кнопка скрыта, чтобы не мешать.
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayback,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.play_arrow, size: 44, color: Colors.white),
                ),
              ),
            ),
          ),
        if (controller != null && controller.value.isInitialized)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ),
        if (_failed)
          const Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              'Не удалось воспроизвести видео на этом устройстве',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        _durationBadge(),
      ],
    );
  }

  /// Статичный кадр до запуска: миниатюра ролика крупным планом.
  Widget _videoFrame() => FutureBuilder<Uint8List?>(
        future: widget.asset.thumbnailData(1080),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(
              child: Icon(Icons.videocam_outlined,
                  size: 48, color: Colors.white54),
            );
          }
          return Image.memory(bytes, fit: BoxFit.contain);
        },
      );

  Widget _durationBadge() {
    final duration = widget.asset.duration;
    if (duration == null) return const SizedBox.shrink();
    return Positioned(
      right: 8,
      top: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            '${duration.inMinutes.toString().padLeft(2, '0')}:'
            '${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
