import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/user_marker.dart';
import 'marker_shape.dart';

/// Default duration of the marker/card appearance animation.
const Duration kMarkerAnimationDuration = Duration(milliseconds: 220);

/// Single place that turns a [UserMarker] model into map widgets.
///
/// Everything the map needs to draw a marker (glyph, selection ring, entrance
/// animation, and the anchored preview card) is produced here so the layer
/// itself only decides *which* markers to show.
class MarkerBuilder extends StatelessWidget {
  const MarkerBuilder({
    super.key,
    required this.marker,
    this.glyphSize,
    this.selected = false,
    this.animate = false,
    this.animationDuration = kMarkerAnimationDuration,
  });

  /// Transparent hit box reserved for the anchored preview card. The card is
  /// bottom-aligned inside it, so the spare space above stays free for the map
  /// behind (transparent areas do not absorb gestures).
  static const double previewWidth = 248;
  static const double previewHeight = 200;

  final UserMarker marker;

  /// Overrides [UserMarker.size]; used by compact previews.
  final double? glyphSize;
  final bool selected;

  /// Plays a scale/fade entrance once per marker element.
  final bool animate;
  final Duration animationDuration;

  /// Parses `#RRGGBB` and tolerates a damaged value instead of throwing.
  static Color parseColorHex(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return const Color(0xFFA67B5B);
    if (normalized.length <= 6) {
      return Color(0xFF000000 | (parsed & 0xFFFFFF));
    }
    return Color(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final size = glyphSize ?? marker.size;
    final glyph = MarkerShape(
      shape: marker.shape,
      color: parseColorHex(marker.colorHex),
      size: size,
    );
    final ring = AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeOut,
      padding: EdgeInsets.all(selected ? 4 : 0),
      decoration: ShapeDecoration(
        shape: const CircleBorder(),
        color: selected
            ? Colors.white.withValues(alpha: 0.30)
            : Colors.transparent,
      ),
      child: glyph,
    );
    if (!animate) return ring;
    return _MarkerAppearance(
      duration: animationDuration,
      child: ring,
    );
  }

  /// Stable identity for the layer: markers persisted without an id still get a
  /// reproducible key, so the entrance animation is not replayed on rebuild.
  static String _keyFor(UserMarker marker) =>
      'marker-${marker.id ?? '${marker.lat}:${marker.lng}:${marker.name}'}';

  /// Minimum comfortable touch target, so small glyphs stay tappable without
  /// growing visually.
  static const double minHitExtent = 44;

  /// The interactive glyph placed on the map for [marker].
  static Marker buildMapMarker({
    required UserMarker marker,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool animate = true,
    Duration animationDuration = kMarkerAnimationDuration,
  }) {
    final glyphExtent = marker.size + (selected ? 12 : 4);
    final extent = math.max(glyphExtent, minHitExtent);
    return Marker(
      key: ValueKey<String>(_keyFor(marker)),
      point: marker.point,
      width: extent,
      height: extent,
      rotate: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Center(
          child: MarkerBuilder(
            marker: marker,
            selected: selected,
            animate: animate,
            animationDuration: animationDuration,
          ),
        ),
      ),
    );
  }

  /// The anchored preview card drawn *above* [marker].
  ///
  /// [width]/[height] describe the transparent hit box; [child] is aligned to
  /// the bottom of that box, so the card tip always touches the marker point
  /// no matter how long the name or description is.
  static Marker buildPreviewMarker({
    required UserMarker marker,
    required Widget child,
    double width = previewWidth,
    double height = previewHeight,
    Duration animationDuration = kMarkerAnimationDuration,
  }) =>
      buildAnchoredPreview(
        markerKey: ValueKey<String>('preview-${_keyFor(marker)}'),
        point: marker.point,
        child: child,
        width: width,
        height: height,
        animationDuration: animationDuration,
      );

  /// The same anchored preview for *any* map object (drawing, measurement,
  /// track): one positioning/animation rule for every object card.
  static Marker buildAnchoredPreview({
    required Key markerKey,
    required LatLng point,
    required Widget child,
    double width = previewWidth,
    double height = previewHeight,
    Duration animationDuration = kMarkerAnimationDuration,
  }) =>
      Marker(
        key: markerKey,
        point: point,
        width: width,
        height: height,
        alignment: Alignment.topCenter,
        rotate: true,
        // The card is pinned to the bottom of the box, so its tip lands on the
        // anchor point even when the description wraps to two lines.
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _MarkerAppearance(
            duration: animationDuration,
            from: 0.85,
            dy: 8,
            child: child,
          ),
        ),
      );
}

/// Scale + fade + slight lift, played once when the widget is inserted.
class _MarkerAppearance extends StatelessWidget {
  const _MarkerAppearance({
    required this.child,
    required this.duration,
    this.from = 0.6,
    this.dy = 0,
  });

  final Widget child;
  final Duration duration;
  final double from;
  final double dy;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, dy * (1 - value)),
          child: Transform.scale(
            scale: from + (1 - from) * value,
            child: child,
          ),
        ),
      ),
    );
  }
}
