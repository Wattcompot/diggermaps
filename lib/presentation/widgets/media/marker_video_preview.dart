import 'package:flutter/material.dart';

import '../../../data/models/marker_media.dart';
import '../../../services/media/marker_media_service.dart';
import '../app_notifications.dart';

/// Opens the primary video externally; no video decoder lives in the map card.
class MarkerVideoPreview extends StatefulWidget {
  const MarkerVideoPreview({
    super.key,
    required this.media,
    this.count = 1,
    this.service,
  });

  final MarkerMedia media;
  final int count;
  final MarkerMediaService? service;

  @override
  State<MarkerVideoPreview> createState() => _MarkerVideoPreviewState();
}

class _MarkerVideoPreviewState extends State<MarkerVideoPreview> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = widget.service ?? MarkerMediaService();
    try {
      await service.openVideo(widget.media);
    } catch (error) {
      if (mounted) {
        AppNotifications.message(
          context,
          MarkerMediaService.describeError(error),
        );
      }
    } finally {
      if (widget.service == null) await service.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Смотреть видео: ${widget.media.name}',
        child: Tooltip(
          message: 'Открыть видео',
          child: InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: <Widget>[
                  if (_busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.play_circle_fill,
                        size: 28, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.count > 1
                                ? 'Видео · ${widget.count}'
                                : 'Видео · Смотреть',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            widget.media.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.media.durationMs != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.media.durationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  const Icon(Icons.open_in_new, size: 12),
                ],
              ),
            ),
          ),
        ),
      );
}
