import 'package:flutter/material.dart';

import '../../../data/models/user_marker.dart';
import '../media/marker_photo_preview.dart';
import '../media/marker_video_preview.dart';
import '../media/marker_voice_player.dart';
import 'marker_builder.dart';
import 'marker_shape.dart';
import 'object_preview_card.dart';

/// Media content for the shared, map-anchored object card.
class MarkerPreviewCard extends StatelessWidget {
  const MarkerPreviewCard({
    super.key,
    required this.marker,
    required this.onTap,
    this.onClose,
    this.maxWidth = 248,
    this.tailGap = 24,
  });

  final UserMarker marker;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final double maxWidth;
  final double tailGap;

  @override
  Widget build(BuildContext context) {
    final photo = marker.primaryPhoto;
    final voice = marker.primaryVoice;
    final video = marker.primaryVideo;
    return ObjectPreviewCard(
      leading: MarkerShape(
        shape: marker.shape,
        color: MarkerBuilder.parseColorHex(marker.colorHex),
        size: 18,
      ),
      title: marker.name,
      subtitle: marker.description,
      onTap: onTap,
      onClose: onClose,
      maxWidth: maxWidth,
      tailGap: tailGap,
      extra: !marker.hasMedia
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (photo != null) ...<Widget>[
                  MarkerPhotoPreview(
                    key: ValueKey('photo-${photo.fileRef}'),
                    media: photo,
                  ),
                  if (marker.photoCount > 1)
                    Text(
                      'Ещё ${marker.photoCount - 1} фото',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
                if (voice != null) ...<Widget>[
                  if (photo != null) const SizedBox(height: 6),
                  MarkerVoicePlayer(
                    key: ValueKey('voice-${voice.fileRef}'),
                    media: voice,
                  ),
                ],
                if (video != null) ...<Widget>[
                  if (photo != null || voice != null) const SizedBox(height: 4),
                  MarkerVideoPreview(
                    key: ValueKey('video-${video.fileRef}'),
                    media: video,
                    count: marker.videoCount,
                  ),
                ],
              ],
            ),
    );
  }
}
