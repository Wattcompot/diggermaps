// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/map_layers.dart';
import '../../../services/tile_cache/network_tile_provider_factory.dart';

class MarkerShape extends StatelessWidget {
  const MarkerShape({
    super.key,
    required this.shape,
    required this.color,
    required this.size,
  });

  final String shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (shape) {
      case 'square':
        return Container(width: size, height: size, color: color);
      case 'triangle':
        return Icon(Icons.change_history, color: color, size: size);
      case 'circle':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
      case 'place':
        return Icon(Icons.place, color: color, size: size);
      case 'flag':
        return Icon(Icons.flag, color: color, size: size);
      case 'star':
        return Icon(Icons.star, color: color, size: size);
      case 'home':
        return Icon(Icons.home, color: color, size: size);
      case 'work':
        return Icon(Icons.work, color: color, size: size);
      default:
        return Icon(Icons.location_on, color: color, size: size);
    }
  }
}

class MarkerMapPreview extends StatelessWidget {
  const MarkerMapPreview({
    super.key,
    required this.point,
    required this.shape,
    required this.colorHex,
    required this.size,
  });

  final LatLng point;
  final String shape;
  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tileProvider = kIsWeb
        ? createNetworkTileProvider()
        : const FMTCStore('base_layers').getTileProvider();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 120,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: MapLayers.esriWorldImagery,
              tileProvider: tileProvider,
              maxZoom: 18,
              panBuffer: 3,
              keepBuffer: 6,
              subdomains: MapLayers.tileSubdomains,
              userAgentPackageName: MapLayers.userAgentPackageName,
            ),
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: point,
                  width: size,
                  height: size,
                  child: MarkerShape(
                    shape: shape,
                    color: _parseColor(colorHex),
                    size: size,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseColor(String value) =>
      Color(int.parse(value.replaceFirst('#', '0xFF')));
}
