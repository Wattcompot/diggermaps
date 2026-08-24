import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/drawing.dart';
import '../../data/models/track.dart';

class HitResult {
  const HitResult.track(this.track) : drawing = null;

  const HitResult.drawing(this.drawing) : track = null;

  final Track? track;
  final Drawing? drawing;
}

class MapInteractionController {
  const MapInteractionController();

  HitResult? hitTest({
    required LatLng point,
    required List<Track> tracks,
    required List<Drawing> drawings,
    required MapCamera camera,
  }) {
    for (final track in tracks.where((item) => item.visible)) {
      if (_isPolylineHit(point, track.points, camera.zoom)) {
        return HitResult.track(track);
      }
    }
    for (final drawing in drawings.where((item) => item.visible)) {
      if (_isDrawingHit(point, drawing, camera.zoom)) {
        return HitResult.drawing(drawing);
      }
    }
    return null;
  }

  bool _isDrawingHit(LatLng point, Drawing drawing, double zoom) {
    if (drawing.type == 'polygon') {
      var inside = false;
      for (var i = 0, j = drawing.points.length - 1;
          i < drawing.points.length;
          j = i++) {
        final a = drawing.points[i];
        final b = drawing.points[j];
        if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
            point.longitude <
                (b.longitude - a.longitude) *
                        (point.latitude - a.latitude) /
                        (b.latitude - a.latitude) +
                    a.longitude) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return _isPolylineHit(point, drawing.points, zoom);
  }

  bool _isPolylineHit(LatLng point, List<LatLng> points, double zoom) {
    final latitudeScale = math.cos(point.latitude * math.pi / 180) * 111320;
    const longitudeScale = 110540.0;
    final px = point.longitude * latitudeScale;
    final py = point.latitude * longitudeScale;
    final hitRadius = math.max(5.0, 40 / math.pow(2, zoom - 14));
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ax = a.longitude * latitudeScale;
      final ay = a.latitude * longitudeScale;
      final bx = b.longitude * latitudeScale;
      final by = b.latitude * longitudeScale;
      final dx = bx - ax;
      final dy = by - ay;
      final length2 = dx * dx + dy * dy;
      final t =
          length2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / length2;
      final clamped = t.clamp(0.0, 1.0);
      if (math.sqrt(math.pow(px - (ax + dx * clamped), 2) +
              math.pow(py - (ay + dy * clamped), 2)) <=
          hitRadius) {
        return true;
      }
    }
    return false;
  }
}
