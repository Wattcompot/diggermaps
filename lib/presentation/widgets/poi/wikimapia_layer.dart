import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/wikimapia_repository.dart';

class WikimapiaLayer extends StatelessWidget {
  const WikimapiaLayer({
    super.key,
    required this.objects,
    required this.polygons,
    required this.activeId,
    required this.onObjectTap,
  });

  final List<WikimapiaObject> objects;
  final Map<String, List<LatLng>> polygons;
  final String? activeId;
  final ValueChanged<String> onObjectTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        PolygonLayer<String>(
          polygons: polygons.entries
              .where((entry) => entry.value.length >= 3)
              .map(
                (entry) => Polygon<String>(
                  points: entry.value,
                  hitValue: entry.key,
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderColor:
                      entry.key == activeId ? Colors.white : Colors.amber,
                  borderStrokeWidth: entry.key == activeId ? 4 : 2,
                ),
              )
              .toList(growable: false),
        ),
        MarkerLayer(
          markers: objects
              .map(
                (object) => Marker(
                  point: object.position,
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => onObjectTap(object.id),
                    icon: Icon(
                      Icons.place,
                      color: object.id == activeId
                          ? Colors.white
                          : Colors.amber.shade700,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}
