import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/map_layers.dart';
import '../../../core/map_tile_provider_factory.dart';
import '../../../data/models/drawing.dart';
import '../../../data/models/track.dart';
import '../../../data/models/user_marker.dart';
import '../../../data/repositories/custom_map_repository.dart';
import '../../../core/map_formats/imported_vector_parser.dart';
import '../../../presentation/providers/drawing_controller.dart';
import '../../../presentation/providers/map_layers_controller.dart';
import '../../../presentation/providers/sentinel_controller.dart';
import '../../../presentation/providers/track_recording_controller.dart';
import '../../../presentation/providers/wikimapia_controller.dart';
import '../../../services/tile_cache/network_tile_provider_factory.dart';
import 'drawing_anchor_layer.dart';
import 'drawing_label_layer.dart';
import 'paint_line_layer.dart';
import 'track_line_layer.dart';
import 'user_marker_layer.dart';
import 'wikimapia_layer.dart';

class MapLayerStack extends StatelessWidget {
  const MapLayerStack({
    super.key,
    required this.mapController,
    required this.layersController,
    required this.drawingController,
    required this.trackController,
    required this.sentinelController,
    required this.wikimapiaController,
    required this.tileProviderFactory,
    required this.defaultSources,
    required this.importedVectors,
    required this.markers,
    required this.drawings,
    required this.temporaryDrawings,
    required this.tracks,
    required this.selectedMarkerId,
    required this.selectedDrawingId,
    required this.selectedTrackId,
    required this.followLocation,
    required this.locationLayerEnabled,
    required this.metricUnits,
    required this.initialCenter,
    required this.onTap,
    required this.onPositionChanged,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onWikimapiaObjectTap,
    required this.onMarkerTap,
    required this.onMarkerLongPress,
  });

  final MapController mapController;
  final MapLayersController layersController;
  final DrawingController drawingController;
  final TrackRecordingController trackController;
  final SentinelController sentinelController;
  final WikimapiaController wikimapiaController;
  final MapTileProviderFactory tileProviderFactory;
  final List<CustomMapLayer> defaultSources;
  final Map<String, List<ImportedVectorGeometry>> importedVectors;
  final List<UserMarker> markers;
  final List<Drawing> drawings;
  final List<Drawing> temporaryDrawings;
  final List<Track> tracks;
  final int? selectedMarkerId;
  final int? selectedDrawingId;
  final int? selectedTrackId;
  final bool followLocation;
  final bool locationLayerEnabled;
  final bool metricUnits;
  final LatLng initialCenter;
  final ValueChanged<LatLng> onTap;
  final void Function(MapCamera camera, bool hasGesture) onPositionChanged;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final void Function(PointerEvent event) onPointerUp;
  final ValueChanged<String> onWikimapiaObjectTap;
  final ValueChanged<UserMarker> onMarkerTap;
  final ValueChanged<UserMarker> onMarkerLongPress;

  double get baseLayerMaxZoom => defaultSources
      .firstWhere(
        (layer) => layer.id == layersController.baseLayerId,
        orElse: () => defaultSources.first,
      )
      .maxZoom
      .toDouble();

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerUp,
      child: GestureDetector(
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 12.8,
            maxZoom: baseLayerMaxZoom,
            backgroundColor: const Color(0xFF1A1A1A),
            interactionOptions: InteractionOptions(
              flags: drawingController.mode == MapDrawingMode.line
                  ? InteractiveFlag.none
                  : InteractiveFlag.all,
              enableMultiFingerGestureRace: true,
              rotationThreshold: 5,
              pinchZoomThreshold: 0.35,
            ),
            onTap: (tapPosition, point) => onTap(point),
            onPositionChanged: onPositionChanged,
          ),
          children: <Widget>[
            _buildBaseTileLayer(),
            if (layersController.baseLayerId == 'esri_world_imagery')
              _tileLayer(MapLayers.esriReference),
            if (sentinelController.visible &&
                sentinelController.tileUrl != null)
              _sentinelTileLayer(),
            ..._enabledCustomLayers(),
            ..._importedMapLayers(),
            Stack(
              children: <Widget>[
                PolylineLayer(polylines: _buildPolylines()),
                PolygonLayer(polygons: _buildPolygons()),
              ],
            ),
            TrackLineLayer(
              lines: tracks
                  .where((track) => track.visible)
                  .map(
                    (track) => TrackLineData(
                      points: track.points,
                      color: Color(track.color),
                      selected: track.id == selectedTrackId,
                    ),
                  )
                  .toList(growable: false),
              activeLine: trackController.activePoints.isEmpty
                  ? null
                  : trackController.activePoints,
            ),
            PaintLineLayer(lines: _buildPaintLines()),
            if (wikimapiaController.enabled)
              WikimapiaLayer(
                objects: wikimapiaController.objects,
                polygons: wikimapiaController.polygonMap,
                activeId: wikimapiaController.activeId,
                onObjectTap: onWikimapiaObjectTap,
              ),
            if (locationLayerEnabled)
              CurrentLocationLayer(
                positionStream: const LocationMarkerDataStreamFactory()
                    .fromGeolocatorPositionStream(
                  stream: Geolocator.getPositionStream(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.best,
                      distanceFilter: 1,
                    ),
                  ),
                ),
                alignPositionOnUpdate:
                    followLocation ? AlignOnUpdate.always : AlignOnUpdate.never,
                alignDirectionOnUpdate:
                    followLocation ? AlignOnUpdate.always : AlignOnUpdate.never,
                alignPositionAnimationDuration:
                    const Duration(milliseconds: 500),
                style: LocationMarkerStyle(
                  marker: const DefaultLocationMarker(
                    color: Color(0xFFA67B5B),
                    child:
                        Icon(Icons.navigation, color: Colors.white, size: 24),
                  ),
                  markerSize: const Size(40, 40),
                  markerDirection: MarkerDirection.heading,
                  accuracyCircleColor:
                      const Color(0xFFA67B5B).withValues(alpha: 0.15),
                  headingSectorColor:
                      const Color(0xFFA67B5B).withValues(alpha: 0.3),
                  headingSectorRadius: 60,
                ),
              ),
            UserMarkerLayer(
              markers: markers,
              selectedMarkerId: selectedMarkerId,
              onMarkerTap: onMarkerTap,
              onMarkerLongPress: onMarkerLongPress,
            ),
            DrawingAnchorLayer(
              activePoints: drawingController.activePoints,
              showActivePoints: drawingController.mode != MapDrawingMode.line,
              drawings: <Drawing>[...drawings, ...temporaryDrawings],
            ),
            DrawingLabelLayer(
              activePoints: drawingController.activePoints,
              showActiveRuler: drawingController.mode == MapDrawingMode.ruler,
              drawings: drawings,
              metric: metricUnits,
            ),
            const RichAttributionWidget(
              attributions: <SourceAttribution>[
                TextSourceAttribution('© OpenStreetMap contributors'),
                TextSourceAttribution('© Esri'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TileLayer _buildBaseTileLayer() {
    final layer = defaultSources.firstWhere(
      (item) => item.id == layersController.baseLayerId,
      orElse: () => defaultSources.firstWhere(
        (item) => item.id == 'esri_world_imagery',
      ),
    );
    return _tileLayer(
      layer.urlTemplate,
      maxZoom: layer.maxZoom.toDouble(),
      storeName: layersController.baseLayerId == 'esri_world_imagery'
          ? 'esri_base'
          : 'base_layers',
    );
  }

  TileLayer _tileLayer(
    String urlTemplate, {
    double maxZoom = 19,
    String storeName = 'base_layers',
  }) {
    return TileLayer(
      key: ValueKey(urlTemplate),
      urlTemplate: urlTemplate,
      fallbackUrl: MapLayers.openStreetMap,
      tileProvider: kIsWeb
          ? createNetworkTileProvider()
          : FMTCStore(storeName).getTileProvider(),
      maxZoom: maxZoom,
      panBuffer: 3,
      keepBuffer: 6,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 150),
      ),
      tileUpdateTransformer:
          TileUpdateTransformers.debounce(const Duration(milliseconds: 200)),
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
      subdomains: MapLayers.tileSubdomains,
      userAgentPackageName: MapLayers.userAgentPackageName,
    );
  }

  TileLayer _sentinelTileLayer() => TileLayer(
        key: ValueKey(
          'imagery-${sentinelController.layerVersion}-'
          '${sentinelController.date.toIso8601String()}-'
          '${sentinelController.tileUrl!}',
        ),
        urlTemplate: sentinelController.tileUrl!,
        tileProvider: sentinelController.tileProvider,
        maxZoom: 19,
        panBuffer: 3,
        keepBuffer: 6,
        tileDisplay: const TileDisplay.instantaneous(),
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
        errorTileCallback: (_, __, ___) {},
      );

  List<Widget> _enabledCustomLayers() {
    return layersController.customMaps
        .where((map) => layersController.enabledCustomMapIds.contains(map.id))
        .map((map) {
      if (kIsWeb && map.sourceType != MapSourceType.network) {
        return const SizedBox.shrink();
      }
      if (map.sourceType == MapSourceType.mbtiles) {
        return Opacity(
          opacity: map.opacity,
          child: TileLayer(
            tileProvider: MbTilesTileProvider(
              mbtiles: tileProviderFactory.mbtiles(map.urlTemplate),
            ),
            maxZoom: map.maxZoom.toDouble(),
            panBuffer: 2,
            keepBuffer: 4,
            tileBuilder: (context, tileWidget, tile) => Transform.translate(
              offset: tileProviderFactory.customLayerScreenOffset(map),
              child: tileWidget,
            ),
          ),
        );
      }
      if (map.sourceType == MapSourceType.ozf2 ||
          map.sourceType == MapSourceType.oziMap) {
        final provider = tileProviderFactory.buildOzf2Provider(map);
        if (provider != null) {
          return Opacity(
            opacity: map.opacity,
            child: TileLayer(
              tileProvider: provider,
              maxZoom: map.maxZoom.toDouble(),
              panBuffer: 2,
              keepBuffer: 4,
            ),
          );
        }
        return const SizedBox.shrink();
      }
      if (map.sourceType == MapSourceType.jnx ||
          map.sourceType == MapSourceType.birdseye) {
        return Opacity(
          opacity: map.opacity,
          child: TileLayer(
            tileProvider: tileProviderFactory.buildJnxProvider(map),
            maxZoom: map.maxZoom.toDouble(),
            panBuffer: 2,
            keepBuffer: 4,
          ),
        );
      }
      if (map.sourceType == MapSourceType.kml ||
          map.sourceType == MapSourceType.kmz ||
          map.sourceType == MapSourceType.gpx) {
        final vectors = importedVectors[map.urlTemplate] ?? const [];
        return Stack(
          children: <Widget>[
            PolylineLayer(
              polylines: vectors
                  .where((geometry) => !geometry.polygon)
                  .map(
                    (geometry) => Polyline(
                      points: geometry.points,
                      color: Colors.orange,
                      strokeWidth: 3,
                    ),
                  )
                  .toList(growable: false),
            ),
            PolygonLayer(
              polygons: vectors
                  .where((geometry) => geometry.polygon)
                  .map(
                    (geometry) => Polygon(
                      points: geometry.points,
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderColor: Colors.orange,
                      borderStrokeWidth: 2,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        );
      }
      if (map.sourceType == MapSourceType.geotiff ||
          map.sourceType == MapSourceType.garminImg) {
        return const SizedBox.shrink();
      }
      return tileProviderFactory.buildNetworkCustomLayer(map);
    }).toList(growable: false);
  }

  List<Widget> _importedMapLayers() {
    return layersController.importedMaps.reversed
        .where((map) => map.visible && map.isRasterOverlay)
        .map((map) =>
            tileProviderFactory.buildImportedLayer(map, baseLayerMaxZoom))
        .whereType<Widget>()
        .toList(growable: false);
  }

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    for (final drawing in drawings) {
      if (drawing.visible &&
          drawing.type == 'line' &&
          drawing.category == 'measurement') {
        final selected = selectedDrawingId == drawing.id;
        if (selected) {
          polylines.add(
            Polyline(
              points: drawing.points,
              strokeWidth: drawing.strokeWidth + 4,
              color: Colors.white,
              pattern: StrokePattern.dashed(segments: const [10, 5]),
            ),
          );
        }
        polylines.add(
          Polyline(
            points: drawing.points,
            strokeWidth: drawing.strokeWidth,
            color: Color(drawing.color),
            pattern: StrokePattern.dashed(segments: const [10, 5]),
          ),
        );
      }
    }
    for (final drawing in temporaryDrawings) {
      if (drawing.type == 'line' && drawing.category == 'measurement') {
        polylines.add(
          Polyline(
            points: drawing.points,
            strokeWidth: drawing.strokeWidth,
            color: Color(drawing.color),
            pattern: const StrokePattern.solid(),
          ),
        );
      }
    }
    if (drawingController.mode == MapDrawingMode.ruler &&
        drawingController.activePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          points: drawingController.activePoints,
          strokeWidth: 3,
          color: Colors.green,
          pattern: StrokePattern.dashed(segments: const [10, 5]),
        ),
      );
    }
    return polylines;
  }

  List<PaintLineData> _buildPaintLines() {
    return <PaintLineData>[
      ...drawings
          .where(
            (drawing) =>
                drawing.visible &&
                drawing.type == 'line' &&
                drawing.category != 'measurement',
          )
          .map(
            (drawing) => PaintLineData(
              points: drawing.points,
              color: Color(drawing.color),
              selected: drawing.id == selectedDrawingId,
            ),
          ),
      ...temporaryDrawings
          .where(
            (drawing) =>
                drawing.type == 'line' && drawing.category != 'measurement',
          )
          .map(
            (drawing) => PaintLineData(
              points: drawing.points,
              color: Color(drawing.color),
              selected: false,
            ),
          ),
      if (drawingController.mode == MapDrawingMode.line &&
          drawingController.activePoints.length > 1)
        PaintLineData(
          points: drawingController.activePoints,
          color: drawingController.color,
          selected: false,
        ),
    ];
  }

  List<Polygon> _buildPolygons() {
    final polygons = <Polygon>[];
    for (final drawing in drawings) {
      if (drawing.visible && drawing.type == 'polygon') {
        final selected = selectedDrawingId == drawing.id;
        if (selected) {
          polygons.add(
            Polygon(
              points: drawing.points,
              color: Colors.transparent,
              borderColor: Colors.white,
              borderStrokeWidth: drawing.strokeWidth + 4,
              pattern: drawing.category == 'measurement'
                  ? StrokePattern.dashed(segments: const [10, 5])
                  : const StrokePattern.solid(),
            ),
          );
        }
        polygons.add(
          Polygon(
            points: drawing.points,
            color: Color(drawing.color).withValues(alpha: drawing.fillOpacity),
            borderColor: Color(drawing.color),
            borderStrokeWidth: drawing.strokeWidth,
            pattern: drawing.category == 'measurement'
                ? StrokePattern.dashed(segments: const [10, 5])
                : const StrokePattern.solid(),
          ),
        );
      }
    }
    for (final drawing in temporaryDrawings) {
      if (drawing.type == 'polygon') {
        polygons.add(
          Polygon(
            points: drawing.points,
            color: Color(drawing.color).withValues(alpha: drawing.fillOpacity),
            borderColor: Color(drawing.color),
            borderStrokeWidth: drawing.strokeWidth,
            pattern: const StrokePattern.solid(),
          ),
        );
      }
    }
    if ((drawingController.mode == MapDrawingMode.polygon ||
            drawingController.mode == MapDrawingMode.planimeter) &&
        drawingController.activePoints.length > 2) {
      polygons.add(
        Polygon(
          points: drawingController.activePoints,
          color: Colors.cyan.withValues(alpha: 0.3),
          borderColor: drawingController.color,
          borderStrokeWidth: drawingController.strokeWidth,
          pattern: const StrokePattern.solid(),
        ),
      );
    }
    return polygons;
  }
}
// ignore_for_file: deprecated_member_use
