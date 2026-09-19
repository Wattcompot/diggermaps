import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/models/marker_media.dart';
import '../../../services/media/marker_media_service.dart';
import '../../../services/media/marker_media_store.dart';
import '../app_notifications.dart';

/// One primary photo; other attachments stay in the marker editor.
class MarkerPhotoPreview extends StatefulWidget {
  const MarkerPhotoPreview({
    super.key,
    required this.media,
    this.store,
    this.height = 92,
  });

  final MarkerMedia media;
  final MarkerMediaStore? store;
  final double height;

  @override
  State<MarkerPhotoPreview> createState() => _MarkerPhotoPreviewState();
}

class _MarkerPhotoPreviewState extends State<MarkerPhotoPreview> {
  late Future<File?> _file;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _file = _resolve();
  }

  @override
  void didUpdateWidget(covariant MarkerPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.fileRef != widget.media.fileRef ||
        oldWidget.store != widget.store) {
      _error = null;
      _file = _resolve();
    }
  }

  Future<File?> _resolve() async {
    try {
      final file = await (widget.store ?? MarkerMediaStore())
          .resolve(widget.media.fileRef);
      if (file == null || !await file.exists()) {
        throw StateError('Файл недоступен: сохранена только ссылка');
      }
      return file;
    } catch (error) {
      // The placeholder is quiet until the user tries to open the photo.
      _error = MarkerMediaService.describeError(error);
      return null;
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    final pending = _file;
    try {
      final file = await pending;
      if (!mounted || pending != _file) return;
      if (file == null || !await file.exists()) {
        throw StateError(_error ?? 'Фотография недоступна');
      }
      if (!mounted || pending != _file) return;
      if (_error != null) throw StateError(_error!);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: InteractiveViewer(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Не удалось открыть фотографию'),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted && pending == _file) {
        AppNotifications.message(
          context,
          MarkerMediaService.describeError(error),
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Открыть фотографию',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: FutureBuilder<File?>(
                future: _file,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _placeholder(Icons.photo_outlined);
                  }
                  final file = snapshot.data;
                  if (file == null) {
                    return _placeholder(Icons.image_not_supported_outlined);
                  }
                  return Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 600,
                    errorBuilder: (_, __, ___) {
                      _error = 'Не удалось открыть фотографию';
                      return _placeholder(Icons.broken_image_outlined);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

  Widget _placeholder(IconData icon) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(child: Icon(icon, size: 24)),
      );
}
