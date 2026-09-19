import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'marker_builder.dart';

class ObjectPreview {
  const ObjectPreview(
      {required this.id, required this.point, required this.child});

  final String id;
  final LatLng point;
  final Widget child;
}

class ObjectPreviewController extends ValueNotifier<ObjectPreview?> {
  ObjectPreviewController() : super(null);

  void toggle(ObjectPreview preview) {
    value = value?.id == preview.id ? null : preview;
  }

  void hide() => value = null;
}

/// Only the card participates in hit testing; the transparent anchor area
/// remains available for map gestures.
class ObjectPreviewLayer extends StatefulWidget {
  const ObjectPreviewLayer({super.key, required this.controller});

  final ObjectPreviewController controller;

  @override
  State<ObjectPreviewLayer> createState() => _ObjectPreviewLayerState();
}

class _ObjectPreviewLayerState extends State<ObjectPreviewLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: kMarkerAnimationDuration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
  );
  ObjectPreview? _displayed;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant ObjectPreviewLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    final next = widget.controller.value;
    if (next != null) {
      final same = next.id == _displayed?.id;
      setState(() => _displayed = next);
      _animation.forward(from: same ? null : 0);
    } else {
      setState(() {});
      _animation.reverse().then((_) {
        if (mounted && widget.controller.value == null) {
          setState(() => _displayed = null);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _displayed;
    return MarkerLayer(markers: <Marker>[
      if (preview != null)
        Marker(
          key: ValueKey('object-preview-${preview.id}'),
          point: preview.point,
          width: 272,
          height: 370,
          alignment: Alignment.topCenter,
          rotate: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: widget.controller.value == null,
              child: FadeTransition(
                opacity: _curve,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .94, end: 1).animate(_curve),
                  alignment: Alignment.bottomCenter,
                  child: KeyedSubtree(
                    key: ValueKey('preview-content-${preview.id}'),
                    child: preview.child,
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
