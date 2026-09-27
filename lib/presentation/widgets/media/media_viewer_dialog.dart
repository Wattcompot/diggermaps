import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Полноэкранный просмотр вложения к метке (фото/кадр видео).
///
/// Зачем отдельный виджет: раньше фото открывалось стандартным [Dialog] с
/// кнопками под картинкой — на телефоне это выглядело чужеродно (светлая
/// плашка, мелкое изображение, кнопки «Закрыть/Удалить» внизу). Здесь
/// затемнённый фон, картинка на всю доступную область, плавное появление,
/// жесты масштабирования и аккуратная нижняя панель действий.
class MediaViewerDialog extends StatefulWidget {
  const MediaViewerDialog({
    super.key,
    required this.file,
    required this.title,
    this.subtitle,
    this.isVideo = false,
    this.onDelete,
    this.onOpenExternal,
  });

  final File file;

  /// Имя файла или подпись вложения.
  final String title;

  /// Дополнительная строка: дата, длительность, размер.
  final String? subtitle;

  /// Для видео вместо картинки показываем кадр-превью и кнопку запуска.
  final bool isVideo;

  /// Удаление вложения. `null` — действие не показывается.
  final VoidCallback? onDelete;

  /// Запуск видео во внешнем проигрывателе.
  final VoidCallback? onOpenExternal;

  /// Открывает просмотрщик с плавным появлением.
  static Future<void> show(
    BuildContext context, {
    required File file,
    required String title,
    String? subtitle,
    bool isVideo = false,
    VoidCallback? onDelete,
    VoidCallback? onOpenExternal,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть просмотр',
      barrierColor: Colors.black.withValues(alpha: 0.86),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) => MediaViewerDialog(
        file: file,
        title: title,
        subtitle: subtitle,
        isVideo: isVideo,
        onDelete: onDelete,
        onOpenExternal: onOpenExternal,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<MediaViewerDialog> createState() => _MediaViewerDialogState();
}

class _MediaViewerDialogState extends State<MediaViewerDialog>
    with SingleTickerProviderStateMixin {
  final TransformationController _zoom = TransformationController();
  late final AnimationController _zoomAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Animation<Matrix4>? _zoomTween;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _zoomAnimation.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _zoom.value = tween.value;
    });
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// Двойной тап: приблизить к точке нажатия или вернуть исходный масштаб.
  void _handleDoubleTap() {
    final details = _doubleTapDetails;
    if (details == null) return;
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.2;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(
            -details.localPosition.dx + 40,
            -details.localPosition.dy + 40,
            0,
            0,
          )
          ..scaleByDouble(2.4, 2.4, 1, 0));
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOutCubic),
    );
    _zoomAnimation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = widget.subtitle;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: _handleDoubleTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      InteractiveViewer(
                        transformationController: _zoom,
                        minScale: 1,
                        maxScale: 4,
                        child: Image.file(
                          widget.file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Не удалось открыть файл',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.isVideo)
                        Center(
                          child: _PlayBadge(
                            onTap: widget.onOpenExternal,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                  ],
                ),
              ),
              if (widget.onDelete != null)
                IconButton(
                  tooltip: 'Удалить',
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete!.call();
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          tooltip: 'Смотреть видео',
          iconSize: 42,
          padding: const EdgeInsets.all(10),
          onPressed: onTap,
          icon: const Icon(Icons.play_arrow, color: Colors.white),
        ),
      );
}

/// Подпись «дата · размер · длительность» для нижней панели просмотрщика.
String mediaViewerSubtitle({
  DateTime? createdAt,
  int? bytes,
  int? durationMs,
}) {
  final parts = <String>[
    if (createdAt != null)
      DateFormat('dd.MM.yyyy, HH:mm').format(createdAt.toLocal()),
    if (durationMs != null)
      '${(durationMs / 1000).round() ~/ 60}:'
          '${((durationMs / 1000).round() % 60).toString().padLeft(2, '0')}',
    if (bytes != null && bytes > 0) _formatBytes(bytes),
  ];
  return parts.join(' · ');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}
