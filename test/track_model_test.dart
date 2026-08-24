import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/data/models/track.dart';

void main() {
  final startedAt = DateTime(2026, 8, 16, 14, 0);

  test('track color is persisted', () {
    final track = Track(
      name: 'Test',
      points: const [LatLng(55, 37), LatLng(55.1, 37.1)],
      distance: 100,
      duration: 10,
      color: 0xFF00A651,
    );

    final restored = Track.fromMap(track.toMap());

    expect(restored.color, 0xFF00A651);
  });

  test('legacy track without color defaults to red', () {
    final map = Track(
      name: 'Legacy',
      points: const [LatLng(55, 37), LatLng(55.1, 37.1)],
      distance: 100,
      duration: 10,
    ).toMap()
      ..remove('color');

    expect(Track.fromMap(map).color, 0xFFFF0000);
  });

  test('track segments are persisted', () {
    final track = Track(
      name: 'Paused',
      points: const [LatLng(55, 37), LatLng(55.1, 37.1)],
      distance: 1200,
      duration: 600,
      segments: [
        TrackSegment(
          type: 'recording',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 10)),
          distance: 1200,
        ),
        TrackSegment(
          type: 'pause',
          startedAt: startedAt.add(const Duration(minutes: 10)),
          endedAt: startedAt.add(const Duration(minutes: 15)),
        ),
      ],
      createdAt: startedAt,
    );

    final restored = Track.fromMap(track.toMap());

    expect(restored.segments, hasLength(2));
    expect(restored.segments[1].isPause, isTrue);
    expect(restored.segments[0].distance, 1200);
  });
}
