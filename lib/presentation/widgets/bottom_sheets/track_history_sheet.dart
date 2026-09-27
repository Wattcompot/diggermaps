import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/track.dart';
import '../object_bottom_sheet.dart';

class TrackHistorySheet {
  const TrackHistorySheet._();

  static Future<void> show(BuildContext context, Track track) {
    final segments = track.segments.isNotEmpty
        ? track.segments
        : <TrackSegment>[
            TrackSegment(
              type: 'recording',
              startedAt: track.createdAt,
              endedAt: track.createdAt.add(Duration(seconds: track.duration)),
              distance: track.distance,
            ),
          ];
    final total = segments.fold<Duration>(
      Duration.zero,
      (sum, segment) => sum + segment.duration,
    );
    final recording =
        segments.where((segment) => !segment.isPause).fold<Duration>(
              Duration.zero,
              (sum, segment) => sum + segment.duration,
            );
    return showObjectBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ObjectBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('История трека',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Начало: '
              '${DateFormat('HH:mm').format(segments.first.startedAt.toLocal())}',
            ),
            Text('Общее время: ${_format(total)}'),
            Text('В записи: ${_format(recording)}'),
            Text(
                'Пауз: ${segments.where((segment) => segment.isPause).length}'),
            const Divider(height: 24),
            ...segments.map(
              (segment) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  segment.isPause ? Icons.pause_circle : Icons.route,
                  color: segment.isPause ? Colors.orange : Color(track.color),
                ),
                title: Text(segment.isPause ? 'Пауза' : 'Запись'),
                subtitle: Text(
                  '${DateFormat('HH:mm').format(segment.startedAt.toLocal())}'
                  '–${DateFormat('HH:mm').format(segment.endedAt.toLocal())} · '
                  '${_format(segment.duration)}'
                  '${segment.isPause ? '' : ' · ${(segment.distance / 1000).toStringAsFixed(2)} км'}',
                ),
              ),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.stop_circle, color: Colors.red),
              title: Text('Стоп'),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
