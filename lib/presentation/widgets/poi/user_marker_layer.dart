import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../data/models/user_marker.dart';
import 'marker_shape.dart';

class UserMarkerLayer extends StatelessWidget {
  const UserMarkerLayer({
    super.key,
    required this.markers,
    required this.selectedMarkerId,
    required this.onMarkerTap,
    required this.onMarkerLongPress,
  });

  final List<UserMarker> markers;
  final int? selectedMarkerId;
  final ValueChanged<UserMarker> onMarkerTap;
  final ValueChanged<UserMarker> onMarkerLongPress;

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: markers.where((marker) => marker.visible).map((marker) {
        final selected = selectedMarkerId == marker.id;
        return Marker(
          point: marker.point,
          width: marker.size + (selected ? 12 : 4),
          height: marker.size + (selected ? 12 : 4),
          rotate: true,
          child: GestureDetector(
            onTap: () => onMarkerTap(marker),
            onLongPress: () => onMarkerLongPress(marker),
            child: DecoratedBox(
              decoration: selected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    )
                  : const BoxDecoration(),
              child: MarkerShape(
                shape: marker.shape,
                color: _parseColor(marker.colorHex),
                size: marker.size,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  static Color _parseColor(String value) =>
      Color(int.parse(value.replaceFirst('#', '0xFF')));
}
