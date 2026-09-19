import 'package:flutter/material.dart';

/// Общая компактная интерактивная плашка объекта карты.
///
/// Одна визуальная система для меток, рисунков и измерений: та же форма,
/// тот же «хвостик» к объекту, та же анимация появления (её даёт
/// `MarkerBuilder.buildPreviewMarker`). Конкретные плашки (`MarkerPreviewCard`,
/// `ShapePreviewCard`) лишь подставляют glyph, заголовок, подзаголовок и
/// дополнительное содержимое.
///
/// Нажатие на плашку — единая точка входа в редактор объекта.
class ObjectPreviewCard extends StatelessWidget {
  const ObjectPreviewCard({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.extra,
    this.onClose,
    this.maxWidth = 224,
    this.tailGap = 24,
  });

  /// Значок объекта слева (форма метки, штрих линии и т.д.).
  final Widget leading;
  final String title;

  /// Описание / метрика (расстояние, площадь). Пустое — не показываем.
  final String? subtitle;

  /// Дополнительный блок под текстом (медиа-сводка, фото и т.п.).
  final Widget? extra;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final double maxWidth;

  /// Зазор между хвостиком и точкой привязки (чтобы не закрывать сам объект).
  final double tailGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleText = subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: leading,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitleText.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              subtitleText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (extra != null) ...<Widget>[
                            const SizedBox(height: 6),
                            extra!,
                          ],
                        ],
                      ),
                    ),
                    if (onClose != null)
                      IconButton(
                        tooltip: 'Скрыть',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: onClose,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Хвостик, указывающий на объект под плашкой.
        CustomPaint(
          size: const Size(14, 7),
          painter: _CaretPainter(color: theme.colorScheme.surface),
        ),
        SizedBox(height: tailGap),
      ],
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => oldDelegate.color != color;
}
