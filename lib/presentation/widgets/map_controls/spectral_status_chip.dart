import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SpectralStatusChip extends StatelessWidget {
  const SpectralStatusChip({
    super.key,
    required this.date,
    required this.cloudCoverage,
    required this.loading,
    required this.onEdit,
    required this.onClose,
  });

  final DateTime date;
  final double cloudCoverage;
  final bool loading;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Positioned(
      left: 16,
      right: 88,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.satellite_alt, size: 18, color: onSurface),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${DateFormat('dd.MM').format(date)} • '
                          'Обл. ${cloudCoverage.round()}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (loading) ...<Widget>[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Изменить дату',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Скрыть снимки',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
