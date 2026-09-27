import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
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
import 'coordinate_grid_layer.dart';
import 'sentinel_imagery_layer.dart';
import 'drawing_anchor_layer.dart';
import 'drawing_label_layer.dart';
import 'location_marker_stream.dart';
import 'paint_line_layer.dart';
import 'track_line_layer.dart';
import 'user_marker_layer.dart';
import 'object_preview_layer.dart';
import 'wikimapia_layer.dart';

/// Коричневый акцент приложения для GPS-маячка и сектора направления.
const Color _locationAccent = Color(0xFFC4956A);

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
    required this.positionStream,
    required this.metricUnits,
    required this.initialCenter,
    this.initialZoom = 2,
    this.onMapReady,
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
    required this.previewController,
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

  /// Общий broadcast-поток позиций (см. `LocationController.positionStream`).
  ///
  /// Передаётся снаружи: создание `Geolocator.getPositionStream()` внутри
  /// `build` пересоздавало подписку на каждый rebuild и маячок пропадал.
  final Stream<Position> positionStream;
  final bool metricUnits;
  final LatLng initialCenter;
  final double initialZoom;
  final VoidCallback? onMapReady;
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
  final ObjectPreviewController previewController;

  /// Единый предел приближения карты.
  ///
  /// Возвращает [MapLayers.maxUserZoom] независимо от выбранного базового слоя:
  /// приближение одинаково для всех источников, а тайлы выше их родного зума
  /// масштабируются (over-zoom), а не пропадают. Используется и как
  /// `MapOptions.maxZoom`, и как `maxZoom` импортированных растровых слоёв.
  double get baseLayerMaxZoom => MapLayers.maxUserZoom;

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
            initialZoom: initialZoom,
            onMapReady: onMapReady,
            maxZoom: baseLayerMaxZoom,
            backgroundColor: const Color(0xFF1A1A1A),
            interactionOptions: InteractionOptions(
              flags: drawingController.mode == MapDrawingMode.line
                  ? InteractiveFlag.none
                  : InteractiveFlag.all,
              // Обычный панорамный жест двумя пальцами больше не «сваливается»
              // в поворот: гонка жестов выключена (масштаб и поворот больше не
              // отбирают жест друг у друга), а порог поворота поднят до
              // библиотечных 20° — карта поворачивается только при осознанном
              // вращении пальцами, а не при лёгком перекосе во время панорамы.
              enableMultiFingerGestureRace: false,
              rotationThreshold: 20,
              pinchZoomThreshold: 0.35,
            ),
            onTap: (tapPosition, point) => onTap(point),
            onPositionChanged: onPositionChanged,
          ),
          children: <Widget>[
            CoordinateGridLayer(metricUnits: metricUnits),
            _buildBaseTileLayer(),
            if (layersController.baseLayerId == 'esri_world_imagery')
              _tileLayer(MapLayers.esriReference),
            SentinelImageryLayer(
              key: const ValueKey('fresh-imagery'),
              controller: sentinelController,
            ),
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
            UserMarkerLayer(
              markers: markers,
              selectedMarkerId: selectedMarkerId,
              onMarkerTap: onMarkerTap,
              onMarkerLongPress: onMarkerLongPress,
              previewController: previewController,
            ),
            DrawingAnchorLayer(
              activePoints: drawingController.activePoints,
              showActivePoints: drawingController.mode != MapDrawingMode.line,
              drawings: <Drawing>[...drawings, ...temporaryDrawings],
            ),
            DrawingLabelLayer(
              activePoints: drawingController.activePoints,
              activeMode: drawingController.mode,
              activeSegments: drawingController.activeSegments,
              drawings: <Drawing>[...drawings, ...temporaryDrawings],
              metric: metricUnits,
            ),
            // Маячок геопозиции — выше пользовательских объектов: своя точка
            // должна быть видна всегда, даже если метка или трек лежат ровно
            // на ней. Поток позиций мемоизируется, иначе слой переподписывался
            // на каждый rebuild карты и маячок пропадал.
            if (locationLayerEnabled)
              LocationMarkerStream(
                stream: positionStream,
                builder: (context, positions, headings) => CurrentLocationLayer(
                  key: const ValueKey('current-location'),
                  positionStream: positions,
                  // Очищенный heading (без NaN/Infinity): иначе битый датчик
                  // ориентации делал Transform.rotate маркера невидимым при
                  // уже пришедшей позиции — «центрируется, но маркер не видно».
                  headingStream: headings,
                  alignPositionOnUpdate: followLocation
                      ? AlignOnUpdate.always
                      : AlignOnUpdate.never,
                  alignDirectionOnUpdate: followLocation
                      ? AlignOnUpdate.always
                      : AlignOnUpdate.never,
                  alignPositionAnimationDuration:
                      const Duration(milliseconds: 500),
                  moveAnimationDuration: const Duration(milliseconds: 400),
                  rotateAnimationDuration: const Duration(milliseconds: 250),
                  style: LocationMarkerStyle(
                    marker: const DefaultLocationMarker(
                      color: _locationAccent,
                      child: Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    markerSize: const Size(28, 28),
                    markerDirection: MarkerDirection.heading,
                    accuracyCircleColor:
                        _locationAccent.withValues(alpha: 0.10),
                    // Мягкий широкий конус: пакетный HeadingSector сам
                    // растворяет цвет радиальным градиентом до нуля, поэтому
                    // достаточно очень низкой базовой альфы и большого радиуса.
                    headingSectorColor: _locationAccent.withValues(alpha: 0.28),
                    headingSectorRadius: 90,
                  ),
                ),
              ),
            ObjectPreviewLayer(controller: previewController),
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
      maxNativeZoom: layer.maxZoom,
      storeName: layersController.baseLayerId == 'esri_world_imagery'
          ? 'esri_base'
          : 'base_layers',
    );
  }

  TileLayer _tileLayer(
    String urlTemplate, {
    int maxNativeZoom = 19,
    String storeName = 'base_layers',
  }) {
    return TileLayer(
      key: ValueKey(urlTemplate),
      urlTemplate: urlTemplate,
      fallbackUrl: MapLayers.openStreetMap,
      tileProvider: tileProviderFactory.baseTileProvider(storeName),
      // Тайлы загружаются до родного максимума источника, а выше — до общего
      // предела [MapLayers.maxUserZoom] — масштабируются (over-zoom), поэтому
      // карта не чернеет при сильном приближении.
      maxNativeZoom: maxNativeZoom,
      maxZoom: MapLayers.maxUserZoom,
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
            maxNativeZoom: map.maxZoom,
            maxZoom: MapLayers.maxUserZoom,
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
              maxNativeZoom: map.maxZoom,
              maxZoom: MapLayers.maxUserZoom,
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
            maxNativeZoom: map.maxZoom,
            maxZoom: MapLayers.maxUserZoom,
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
    if ((drawingController.mode == MapDrawingMode.ruler ||
            drawingController.mode == MapDrawingMode.planimeter ||
            drawingController.mode == MapDrawingMode.polygon) &&
        drawingController.activePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: drawingController.activePoints,
          strokeWidth: drawingController.strokeWidth,
          color: drawingController.color,
          pattern: drawingController.mode == MapDrawingMode.polygon
              ? const StrokePattern.solid()
              : StrokePattern.dashed(segments: const [10, 5]),
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
              segments: drawing.segments,
              width: drawing.strokeWidth,
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
              segments: drawing.segments,
              width: drawing.strokeWidth,
              color: Color(drawing.color),
              selected: false,
            ),
          ),
      if (drawingController.mode == MapDrawingMode.line &&
          drawingController.activePoints.length > 1)
        PaintLineData(
          points: drawingController.activePoints,
          segments: drawingController.activeSegments,
          width: drawingController.strokeWidth,
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
            pattern: drawing.category == 'measurement'
                ? StrokePattern.dashed(segments: const [10, 5])
                : const StrokePattern.solid(),
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
          color: drawingController.color.withValues(alpha: 0.3),
          borderColor: drawingController.color,
          borderStrokeWidth: drawingController.strokeWidth,
          pattern: drawingController.mode == MapDrawingMode.planimeter
              ? StrokePattern.dashed(segments: const [10, 5])
              : const StrokePattern.solid(),
        ),
      );
    }
    return polygons;
  }
}
// ignore_for_file: deprecated_member_use
