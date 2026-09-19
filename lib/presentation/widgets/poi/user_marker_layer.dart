import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../data/models/user_marker.dart';
import 'marker_builder.dart';
import 'marker_preview_card.dart';
import 'object_preview_layer.dart';

class UserMarkerLayer extends StatefulWidget {
  const UserMarkerLayer({
    super.key,
    required this.markers,
    required this.onMarkerTap,
    required this.onMarkerLongPress,
    this.selectedMarkerId,
    this.previewController,
    this.animateMarkers = true,
    this.animationDuration = kMarkerAnimationDuration,
  });

  final List<UserMarker> markers;
  final int? selectedMarkerId;
  final ValueChanged<UserMarker> onMarkerTap;
  final ValueChanged<UserMarker> onMarkerLongPress;
  final ObjectPreviewController? previewController;
  final bool animateMarkers;
  final Duration animationDuration;

  @override
  State<UserMarkerLayer> createState() => _UserMarkerLayerState();
}

class _UserMarkerLayerState extends State<UserMarkerLayer> {
  final _localPreview = ObjectPreviewController();
  ObjectPreviewController get _preview =>
      widget.previewController ?? _localPreview;

  String _id(UserMarker marker) =>
      'marker-${marker.id ?? '${marker.lat}:${marker.lng}:${marker.name}'}';

  void _handleMarkerTap(UserMarker marker) {
    _preview.toggle(ObjectPreview(
      id: _id(marker),
      point: marker.point,
      child: MarkerPreviewCard(
        marker: marker,
        onTap: () {
          _preview.hide();
          widget.onMarkerTap(marker);
        },
        onClose: _preview.hide,
      ),
    ));
  }

  @override
  void didUpdateWidget(covariant UserMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = _preview.value?.id;
    if (id != null &&
        id.startsWith('marker-') &&
        !widget.markers.any((marker) => marker.visible && _id(marker) == id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _preview.value?.id == id) _preview.hide();
      });
    }
  }

  @override
  void dispose() {
    _localPreview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          MarkerLayer(markers: <Marker>[
            for (final marker
                in widget.markers.where((marker) => marker.visible))
              MarkerBuilder.buildMapMarker(
                marker: marker,
                selected: widget.selectedMarkerId == marker.id,
                animate: widget.animateMarkers,
                animationDuration: widget.animationDuration,
                onTap: () => _handleMarkerTap(marker),
                onLongPress: () {
                  _preview.hide();
                  widget.onMarkerLongPress(marker);
                },
              ),
          ]),
          if (widget.previewController == null)
            ObjectPreviewLayer(controller: _localPreview),
        ],
      );
}
