import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../data/models/marker_media.dart';
import '../../../services/media/marker_media_service.dart';
import '../app_notifications.dart';
import 'device_gallery_sheet.dart';
import 'marker_voice_player.dart';
import 'marker_video_preview.dart';
import 'media_viewer_dialog.dart';

/// Attachment editor for a user marker: gallery photos, Android camera shots and
/// voice notes (record/play/delete) for Windows and Android.
///
/// The widget owns the *interaction* only; the host (marker editor sheet) owns
/// the resulting [MarkerMedia] list and decides what happens to the files when
/// the edit is committed or cancelled.
class MarkerMediaSection extends StatefulWidget {
  const MarkerMediaSection({
    super.key,
    required this.media,
    required this.onChanged,
    this.service,
    this.enabled = true,
    this.onDraftCreated,
    this.descriptionController,
    this.gallerySource,
  });

  final List<MarkerMedia> media;

  /// Called with the full new list after every add/remove.
  final ValueChanged<List<MarkerMedia>> onChanged;

  /// Injected by the host so playback/recording outlive rebuilds. When omitted
  /// the section creates and disposes its own instance.
  final MarkerMediaService? service;

  final bool enabled;
  final TextEditingController? descriptionController;

  /// Reports a file that this editing session created. Cancelling the session
  /// must delete those files; the saved attachments are never reported.
  final ValueChanged<String>? onDraftCreated;

  /// Источник встроенной галереи. По умолчанию — чтение медиатеки устройства
  /// через `photo_manager`; в тестах подменяется без плагина.
  final DeviceGallerySource? gallerySource;

  @override
  State<MarkerMediaSection> createState() => MarkerMediaSectionState();
}

class MarkerMediaSectionState extends State<MarkerMediaSection>
    with WidgetsBindingObserver {
  late MarkerMediaService _service;
  late bool _ownsService;
  late List<MarkerMedia> _media;

  final Map<String, Future<File?>> _resolvedFiles = <String, Future<File?>>{};
  final Set<String> _sessionRefs = <String>{};
  Timer? _ticker;
  final Stopwatch _recordClock = Stopwatch();
  bool _busy = false;
  bool _recording = false;
  bool _showAll = false;
  static const _collapsedCount = 3;
  String? _replacementVoiceRef;

  bool get isRecording => _recording;
  bool get isBusy => _busy;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MarkerMediaService();
    _ownsService = widget.service == null;
    _media = List<MarkerMedia>.of(widget.media);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MarkerMediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameRefs(oldWidget.media, widget.media) &&
        !_sameRefs(_media, widget.media)) {
      _media = List<MarkerMedia>.of(widget.media);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    if (_recording) {
      // Never leave a half-written draft behind on a closed editor.
      unawaited(_service.cancelRecording());
    }
    if (_ownsService) unawaited(_service.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The gallery and the camera bring the app to inactive/paused; a recording
    // must not silently continue (or stay half-written) across that.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_recording) unawaited(_finishRecording(notify: false));
      return;
    }
    if (state == AppLifecycleState.detached && _recording) {
      unawaited(_service.cancelRecording());
      _stopTicker();
      if (mounted) setState(() => _recording = false);
    }
  }

  static bool _sameRefs(List<MarkerMedia> a, List<MarkerMedia> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].fileRef != b[index].fileRef) return false;
    }
    return true;
  }

  void _notify(String message) =>
      AppNotifications.show(context, SnackBar(content: Text(message)));

  void _notifyError(Object error) =>
      _notify(MarkerMediaService.describeError(error));

  void _emit() => widget.onChanged(List<MarkerMedia>.unmodifiable(_media));

  /// Registers an attachment that was just copied into the managed folder.
  @visibleForTesting
  void addImportedMedia(MarkerMedia media) {
    _sessionRefs.add(media.fileRef);
    widget.onDraftCreated?.call(media.fileRef);
    final replacement = media.isVoice ? _replacementVoiceRef : null;
    final index = _media.indexWhere((item) => item.fileRef == replacement);
    _media = List<MarkerMedia>.of(_media);
    if (index >= 0) {
      final previous = _media[index];
      _media[index] = media;
      unawaited(_discardReplacedDraft(previous));
    } else {
      _media.add(media);
    }
    if (media.isVoice) _replacementVoiceRef = null;
    if (mounted) setState(() {});
    _emit();
  }

  Future<File?> _fileFor(MarkerMedia media) => _resolvedFiles.putIfAbsent(
        media.fileRef,
        () async {
          try {
            return await _service.store.resolve(media.fileRef);
          } catch (_) {
            return null;
          }
        },
      );

  Future<void> _discardReplacedDraft(MarkerMedia previous) async {
    if (_sessionRefs.remove(previous.fileRef)) {
      await _evictFromImageCache(previous.fileRef);
      await _service.store.delete(previous.fileRef);
    }
  }

  Future<void> _pick(
      {required bool video, required bool camera, MarkerMedia? replace}) async {
    if (_busy || !widget.enabled) return;
    if (_recording) await _finishRecording(notify: false);
    if (!mounted) return;

    // Выбор без камеры на Android идёт через встроенную галерею приложения:
    // системный файловый менеджер не открывается. Камера и Windows остаются
    // на прежних пикерах (image_picker / file_picker).
    if (!camera && _service.inAppGallerySupported) {
      await _pickFromInAppGallery(video: video, replace: replace);
      return;
    }

    setState(() => _busy = true);
    try {
      final media = video
          ? await _service.pickVideo(camera: camera)
          : await _service.pickPhoto(camera: camera);
      if (media == null) return;
      if (!mounted) {
        await _service.store.delete(media.fileRef);
        return;
      }
      _acceptPicked(media, replace: replace);
    } catch (error) {
      if (mounted) _notifyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromInAppGallery({
    required bool video,
    MarkerMedia? replace,
  }) async {
    setState(() => _busy = true);
    try {
      final picks = await DeviceGallerySheet.show(
        context,
        source: widget.gallerySource,
        initialVideo: video,
        maxSelection:
            replace == null ? DeviceGallerySheet.defaultMaxSelection : 1,
      );
      if (!mounted || picks == null || picks.isEmpty) return;
      for (final pick in picks) {
        final media = pick.isVideo
            ? await _service.importVideo(pick.path)
            : await _service.importPhoto(pick.path);
        if (!mounted) {
          await _service.store.delete(media.fileRef);
          return;
        }
        _acceptPicked(media, replace: replace);
        // Замена всегда одиночная: первый файл заменяет старое вложение,
        // остальные для неё лишние, поэтому цикл прерывается.
        if (replace != null) break;
      }
    } catch (error) {
      if (mounted) _notifyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _acceptPicked(MarkerMedia media, {MarkerMedia? replace}) {
    if (replace == null) {
      addImportedMedia(media);
      return;
    }
    final index = _media.indexWhere((item) => item.fileRef == replace.fileRef);
    if (index < 0) {
      unawaited(_service.store.delete(media.fileRef));
      return;
    }
    _sessionRefs.add(media.fileRef);
    widget.onDraftCreated?.call(media.fileRef);
    setState(() {
      _media = List<MarkerMedia>.of(_media)..[index] = media;
    });
    _emit();
    unawaited(_discardReplacedDraft(replace));
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_recording) {
      await _finishRecording(notify: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.stopPlayback();
      await _service.startRecording();
      if (!mounted) {
        await _service.cancelRecording();
        return;
      }
      _startTicker();
      setState(() {
        _recording = true;
      });
    } catch (error) {
      if (mounted) _notifyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> prepareToSave() async {
    if (_busy) {
      _notify('Дождитесь завершения операции с вложением');
      return false;
    }
    return !_recording || await _finishRecording(notify: true);
  }

  Future<bool> _finishRecording({required bool notify}) async {
    if (_busy || !_recording) return false;
    setState(() => _busy = true);
    _stopTicker();
    try {
      final media = await _service.stopRecording();
      if (!mounted) {
        await _service.store.delete(media.fileRef);
        return false;
      }
      setState(() => _recording = false);
      addImportedMedia(media);
      if (notify) _notify('Голосовая заметка добавлена');
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _replacementVoiceRef = null;
        });
        if (notify) _notifyError(error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRecording() async {
    _stopTicker();
    await _service.cancelRecording();
    if (mounted) {
      setState(() {
        _recording = false;
        _replacementVoiceRef = null;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _recordClock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _recordClock.stop();
  }

  Future<void> _remove(MarkerMedia media) async {
    _media = _media
        .where((item) => item.fileRef != media.fileRef)
        .toList(growable: false);
    _resolvedFiles.remove(media.fileRef);
    if (mounted) setState(() {});
    _emit();
    // A draft belongs to nobody yet: drop the file at once. Attachments that
    // are already part of the saved marker are removed by the repository once
    // the edit is committed, so cancelling an edit can never lose them.
    if (_sessionRefs.remove(media.fileRef)) {
      // Let Image.file detach its stream before releasing the Windows handle.
      await WidgetsBinding.instance.endOfFrame;
      await _evictFromImageCache(media.fileRef);
      await _service.store.delete(media.fileRef);
    }
  }

  /// Windows keeps a handle on a file that is currently shown by `Image.file`,
  /// so the cached image must be dropped before the file can be deleted.
  Future<void> _evictFromImageCache(String ref) async {
    try {
      final file = await _service.store.resolve(ref);
      if (file == null) return;
      PaintingBinding.instance.imageCache
          .evict(FileImage(file), includeLive: true);
    } catch (_) {
      // Not rendered / no binding — nothing to evict.
    }
  }

  Future<void> _openPhoto(MarkerMedia media) async {
    final file = await _fileFor(media);
    final exists = file != null && await file.exists();
    if (!mounted) return;
    if (!exists) {
      _notify('Файл недоступен: сохранена только ссылка');
      return;
    }
    // Единый просмотрщик вложений: тёмный фон, масштабирование, аккуратные
    // действия внизу вместо прежнего светлого диалога с картинкой.
    await MediaViewerDialog.show(
      context,
      file: file,
      title: media.name,
      subtitle: mediaViewerSubtitle(
        createdAt: media.createdAt,
        bytes: media.bytes,
        durationMs: media.durationMs,
      ),
      onDelete: () => unawaited(_remove(media)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = _service.supported && widget.enabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.descriptionController != null)
            TextField(
                controller: widget.descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Описание',
                    hintText: 'Что здесь интересного?',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true)),
          Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _pickerButton(
                    'Фото', Icons.photo_camera_outlined, false, supported),
                _pickerButton(
                    'Видео', Icons.videocam_outlined, true, supported),
                TextButton.icon(
                    onPressed: supported && !_busy ? _toggleRecording : null,
                    icon: Icon(_recording ? Icons.stop : Icons.mic_none,
                        size: 18),
                    label: Text(_recording ? 'Стоп' : 'Голос')),
                if (_busy)
                  const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
          if (_recording)
            Row(children: <Widget>[
              const Icon(Icons.fiber_manual_record,
                  color: Colors.red, size: 12),
              const SizedBox(width: 6),
              Text(_formatDuration(_recordClock.elapsedMilliseconds)),
              TextButton(
                  onPressed: _cancelRecording, child: const Text('Отменить')),
            ]),
          if (!_service.supported)
            Text('Вложения доступны на Android и Windows',
                style: theme.textTheme.bodySmall),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              for (final media
                  in _showAll ? _media : _media.take(_collapsedCount))
                Padding(
                  key: ValueKey(media.fileRef),
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: <Widget>[
                    Expanded(
                        child: media.isPhoto
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: _PhotoTile(
                                    media: media,
                                    file: _fileFor(media),
                                    onOpen: () => _openPhoto(media),
                                    onDelete: () => _remove(media)))
                            : media.isVideo
                                ? MarkerVideoPreview(
                                    media: media, service: _service)
                                : MarkerVoicePlayer(
                                    key: ValueKey('voice-${media.fileRef}'),
                                    media: media,
                                    store: _service.store)),
                    if (supported)
                      IconButton(
                          tooltip: 'Заменить',
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          onPressed: _busy || _recording
                              ? null
                              : () {
                                  if (media.isVoice) {
                                    _replacementVoiceRef = media.fileRef;
                                    _toggleRecording();
                                  } else {
                                    _pick(
                                        video: media.isVideo,
                                        camera: false,
                                        replace: media);
                                  }
                                }),
                    if (!media.isPhoto)
                      IconButton(
                          tooltip: 'Удалить',
                          onPressed:
                              widget.enabled ? () => _remove(media) : null,
                          icon: const Icon(Icons.delete_outline, size: 20)),
                  ]),
                ),
              // Свёрнутый список показывает только первые [_collapsedCount]
              // вложений, поэтому остальным нужна явная точка раскрытия —
              // иначе они недостижимы из редактора.
              if (_media.length > _collapsedCount)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(_showAll
                        ? 'Свернуть'
                        : 'Ещё ${_media.length - _collapsedCount}'),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pickerButton(
      String label, IconData icon, bool video, bool supported) {
    if (!_service.cameraSupported) {
      return TextButton.icon(
          onPressed: supported && !_busy
              ? () => _pick(video: video, camera: false)
              : null,
          icon: Icon(icon, size: 18),
          label: Text(label));
    }
    return PopupMenuButton<bool>(
      enabled: supported && !_busy,
      tooltip: 'Добавить ${label.toLowerCase()}',
      onSelected: (camera) => _pick(video: video, camera: camera),
      itemBuilder: (_) => <PopupMenuEntry<bool>>[
        // Название пункта отражает фактический маршрут выбора: на Android это
        // встроенная галерея приложения, на Windows — системный диалог файлов.
        PopupMenuItem(
          value: false,
          child: Text(
            _service.inAppGallerySupported ? 'Из галереи' : 'Выбрать файл',
          ),
        ),
        const PopupMenuItem(value: true, child: Text('Снять на камеру')),
      ],
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(label),
          ])),
    );
  }

  static String _formatDuration(int milliseconds) {
    final total = (milliseconds / 1000).floor();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.media,
    required this.file,
    required this.onOpen,
    required this.onDelete,
  });

  final MarkerMedia media;
  final Future<File?> file;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _readPhoto();
  }

  Future<Uint8List?> _readPhoto() async {
    try {
      final file = await widget.file;
      return file == null ? null : await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: widget.onOpen,
                child: FutureBuilder<Uint8List?>(
                  future: _bytes,
                  builder: (context, snapshot) {
                    final resolved = snapshot.data;
                    if (resolved == null) {
                      return ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported_outlined),
                      );
                    }
                    return Image.memory(
                      resolved,
                      cacheWidth: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton.filledTonal(
              tooltip: 'Удалить',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              iconSize: 14,
              onPressed: widget.onDelete,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}
