// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/map_tile_provider_factory.dart';
import '../../data/models/drawing.dart';
import '../../data/models/track.dart';
import '../../data/models/user_marker.dart';
import '../../data/repositories/custom_map_repository.dart';
import '../../data/repositories/map_catalog_repository.dart';
import '../../data/repositories/imported_map_repository.dart';
import '../../data/repositories/search_repository.dart';
import 'import_map_screen.dart';
import '../../data/repositories/sentinel_repository.dart';
import '../../data/repositories/wikimapia_repository.dart';
import '../../data/utils/gpx_exporter.dart';
import '../../data/utils/measurement_utils.dart';
import 'my_maps_screen.dart';
import 'my_objects_screen.dart';
import 'direction_screen.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/app_notifications.dart';
import '../widgets/map_controls/map_bottom_dock.dart';
import '../widgets/confirm_object_delete.dart';
import '../providers/drawing_controller.dart';
import '../providers/map_aiming_controller.dart';
import '../providers/location_controller.dart';
import '../providers/map_calibration_controller.dart';
import '../providers/map_data_controller.dart';
import '../providers/map_interaction_controller.dart';
import '../providers/map_layers_controller.dart';
import '../providers/map_search_controller.dart';
import '../providers/sentinel_controller.dart';
import '../providers/track_recording_controller.dart';
import '../providers/wikimapia_controller.dart';
import '../widgets/bottom_sheets/add_actions_sheet.dart';
import '../widgets/bottom_sheets/base_layer_sheet.dart';
import '../widgets/bottom_sheets/drawing_bottom_sheet.dart';
import '../widgets/bottom_sheets/drawing_save_sheet.dart';
import '../widgets/bottom_sheets/marker_actions_sheet.dart';
import '../widgets/bottom_sheets/marker_bottom_sheet.dart';
import '../widgets/bottom_sheets/marker_create_dialog.dart';
import '../widgets/bottom_sheets/marker_style_picker_sheet.dart';
import '../widgets/bottom_sheets/navigation_chooser_sheet.dart';
import '../widgets/bottom_sheets/offset_editor_dialog.dart';
import '../widgets/bottom_sheets/sentinel_calendar_dialog.dart';
import '../widgets/bottom_sheets/settings_sheet.dart';
import '../widgets/bottom_sheets/track_bottom_sheet.dart';
import '../widgets/bottom_sheets/track_history_sheet.dart';
import '../widgets/bottom_sheets/wikimapia_object_sheet.dart';
import '../widgets/map_controls/bottom_actions.dart';
import '../widgets/map_controls/calibration_controls.dart';
import '../widgets/map_controls/drawing_status_bar.dart';
import '../widgets/map_controls/left_panel.dart';
import '../widgets/map_controls/map_drawer.dart';
import '../widgets/map_controls/opacity_control.dart';
import '../widgets/map_controls/recording_overlay.dart';
import '../widgets/map_controls/search_results_panel.dart';
import '../widgets/map_controls/spectral_status_chip.dart';
import '../widgets/map_controls/top_bar.dart';
import '../widgets/poi/map_layer_stack.dart';
import '../widgets/poi/marker_shape.dart';
import '../widgets/poi/object_preview_card.dart';
import '../widgets/poi/object_preview_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Обзор мира до восстановления камеры или первого валидного GPS-фикса.
  static const _initialPosition = LatLng(0, 0);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  late final TrackRecordingController _trackRecordingController;
  late final DrawingController _drawingController;
  late final MapSearchController _mapSearchController;
  late final MapLayersController _mapLayersController;
  late final MapCalibrationController _calibrationController;
  late final MapDataController _mapDataController;
  late final LocationController _locationController;
  late final SentinelController _sentinelController;
  late final WikimapiaController _wikimapiaController;
  late final MapAimingController _mapAimingController;
  final MapInteractionController _mapInteractionController =
      const MapInteractionController();
  late final MapTileProviderFactory _tileProviderFactory;

  final WikimapiaRepository _wikimapiaRepository = WikimapiaRepository();
  final SentinelRepository _sentinelRepository = SentinelRepository();
  final CustomMapRepository _customMapRepository = CustomMapRepository();
  final SearchRepository _searchRepository = SearchRepository();
  final MapCatalogRepository _mapCatalogRepository = MapCatalogRepository();
  final ImportedMapRepository _importedMapRepository = ImportedMapRepository();
  late final List<CustomMapLayer> _defaultMapSources;

  bool _metricUnits = true;

  double get _baseLayerMaxZoom => _defaultMapSources
      .firstWhere(
        (layer) => layer.id == _mapLayersController.baseLayerId,
        orElse: () => _defaultMapSources.first,
      )
      .maxZoom
      .toDouble();

  int? _selectedDrawingId;
  int? _selectedMarkerId;
  int? _selectedTrackId;
  bool _objectModalSheetOpen = false;
  final _objectPreview = ObjectPreviewController();

  StreamSubscription<MapEvent>? _mapEventSubscription;
  double _mapRotation = 0;
  int _objectHighlightGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationController = LocationController(
      mapController: _mapController,
      onMessage: _showMessage,
    );
    _trackRecordingController = TrackRecordingController(
      ensureLocationPermission: _locationController.handleLocationPermission,
    );
    _drawingController = DrawingController();
    _mapSearchController = MapSearchController(
      repository: _searchRepository,
      onError: _showMessage,
    );
    _mapLayersController = MapLayersController(
      importedMapRepository: _importedMapRepository,
      customMapRepository: _customMapRepository,
    );
    _calibrationController = MapCalibrationController(
      mapController: _mapController,
      layersController: _mapLayersController,
      importedMapRepository: _importedMapRepository,
    );
    _mapDataController = MapDataController(
      customMapRepository: _customMapRepository,
      importedMapRepository: _importedMapRepository,
      layersController: _mapLayersController,
    );
    _sentinelController = SentinelController(
      repository: _sentinelRepository,
      visibleBounds: () => _mapController.camera.visibleBounds,
      onError: _showMessage,
      onCalendarRequested: _showSentinelCalendar,
    );
    _wikimapiaController = WikimapiaController(
      repository: _wikimapiaRepository,
      onError: (message) => _showErrorDialog('Ошибка Wikimapia', message),
    );
    _mapAimingController = MapAimingController(
      canStartFromLongPress: () =>
          _drawingController.mode == MapDrawingMode.view,
      onAimingStarted: _showAimingHint,
      onFinishRequested: _finishAimingAtCurrentCenter,
    );
    _tileProviderFactory = MapTileProviderFactory(
      camera: () => _mapController.camera,
      onProviderReady: _refreshScreen,
    );
    for (final controller in <ChangeNotifier>[
      _locationController,
      _trackRecordingController,
      _drawingController,
      _mapLayersController,
      _calibrationController,
      _mapDataController,
      _sentinelController,
      _wikimapiaController,
      _mapAimingController,
    ]) {
      controller.addListener(_refreshScreen);
    }
    _defaultMapSources = _mapCatalogRepository.getDefaultSources();
    _mapEventSubscription = _mapController.mapEventStream.listen((event) {
      if (event is! MapEventRotate && event is! MapEventRotateEnd) return;
      if (!mounted) return;
      final rotation = event.camera.rotation;
      if ((_mapRotation - rotation).abs() > 0.01) {
        setState(() => _mapRotation = rotation);
      }
    });
    _mapLayersController.watchImportedMaps();
    _initData();
  }

  Future<void> _initData() async {
    await _mapDataController.loadAll();
  }

  Future<void> _resetMapRotation() async {
    final start = _mapController.camera.rotation;
    for (var i = 1; i <= 10; i++) {
      if (!mounted) return;
      _mapController.rotate(start * (1 - i / 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in <ChangeNotifier>[
      _locationController,
      _trackRecordingController,
      _drawingController,
      _mapLayersController,
      _calibrationController,
      _mapDataController,
      _sentinelController,
      _wikimapiaController,
      _mapAimingController,
    ]) {
      controller.removeListener(_refreshScreen);
      controller.dispose();
    }
    _objectPreview.dispose();
    _mapSearchController.dispose();
    _tileProviderFactory.dispose();
    _mapEventSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _refreshScreen() {
    if (!mounted) return;
    _calibrationController.syncImportedMaps();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Камера, галерея и запрос разрешения временно уводят приложение в фон.
    // Редактор и его черновик должны переживать это; запись останавливает
    // собственный lifecycle-обработчик MarkerMediaSection.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _locationController.flushCamera();
    }
  }

  void _closeObjectDetailsSheets() {
    _objectPreview.hide();
    if (_objectModalSheetOpen && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    Future<void> launchSupport(Uri uri) async {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // A clear fallback is shown below.
      }
      if (mounted) _showMessage('Скоро');
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: MapDrawer(
        markers: _mapDataController.myMarkers,
        drawings: _mapDataController.myDrawings,
        tracks: _mapDataController.myTracks,
        importedCount: _mapLayersController.importedMaps.length,
        customCount: _mapLayersController.customMaps.length,
        onMyObjectsTap: _openMyObjectsScreen,
        onMyMapsTap: _openMyMapsScreen,
        onSettingsTap: () => SettingsSheet.show(
          context,
          initialCleanupDays: 30,
          metricUnits: _metricUnits,
          onMetricChanged: (value) => setState(() => _metricUnits = value),
          onCleanupDaysChanged: (_) {},
          onClearCache: () {},
        ),
        onAboutTap: () => showAboutDialog(
          context: context,
          applicationName: 'DiggerMaps',
          applicationVersion: '0.1.0',
          applicationLegalese: 'Полевые карты и находки',
        ),
        onAuthTap: () => _showMessage('Авторизация скоро будет доступна'),
        onPremiumTap: () => _showMessage('Функция в разработке'),
        onSupportEmailTap: () => launchSupport(
          Uri(scheme: 'mailto', path: 'support@diggermaps.ru'),
        ),
        onSupportSiteTap: () => launchSupport(
          Uri.parse('https://diggermaps.ru'),
        ),
        onSupportDocsTap: () => _showMessage('Скоро'),
      ),
      body: Stack(
        children: <Widget>[
          MapLayerStack(
            mapController: _mapController,
            layersController: _mapLayersController,
            drawingController: _drawingController,
            trackController: _trackRecordingController,
            sentinelController: _sentinelController,
            wikimapiaController: _wikimapiaController,
            tileProviderFactory: _tileProviderFactory,
            defaultSources: _defaultMapSources,
            importedVectors: _mapDataController.importedVectors,
            markers: _mapDataController.myMarkers,
            drawings: _mapDataController.myDrawings,
            temporaryDrawings: _mapDataController.temporaryDrawings,
            tracks: _mapDataController.myTracks,
            previewController: _objectPreview,
            selectedMarkerId: _selectedMarkerId,
            selectedDrawingId: _selectedDrawingId,
            selectedTrackId: _selectedTrackId,
            followLocation: _locationController.followLocation,
            locationLayerEnabled: _locationController.locationLayerEnabled,
            positionStream: _locationController.positionStream,
            metricUnits: _metricUnits,
            initialCenter:
                _locationController.savedCamera?.center ?? _initialPosition,
            initialZoom: _locationController.savedCamera?.zoom ?? 2,
            onMapReady: _locationController.restoreCameraOnReady,
            onTap: _handleMapTap,
            onPositionChanged: _handleMapPositionChanged,
            onPanStart: _drawingController.mode == MapDrawingMode.line
                ? (details) {
                    final point = _mapController.camera.offsetToCrs(
                      details.localPosition,
                    );
                    _drawingController.beginFreehand(
                      details.localPosition,
                      point,
                    );
                  }
                : null,
            onPanUpdate: _drawingController.mode == MapDrawingMode.line
                ? (details) {
                    final point = _mapController.camera.offsetToCrs(
                      details.localPosition,
                    );
                    _drawingController.addFreehandSample(
                      details.localPosition,
                      point,
                    );
                  }
                : null,
            onPointerDown: _mapAimingController.onPointerDown,
            onPointerMove: _mapAimingController.onPointerMove,
            onPointerUp: _mapAimingController.onPointerUp,
            onWikimapiaObjectTap: (id) async {
              _wikimapiaController.setActiveId(id);
              final objectId = int.tryParse(id);
              if (objectId == null || objectId <= 0) {
                _showMessage('Некорректный ID объекта');
                return;
              }
              try {
                final place =
                    await _wikimapiaController.showObjectDetails(objectId);
                if (!context.mounted || place == null) return;
                await WikimapiaObjectSheet.show(context, place: place);
              } catch (error) {
                if (error is WikimapiaRateLimitException) {
                  _showMessage('Слишком много запросов к Wikimapia');
                } else if (error is WikimapiaApiLimitException) {
                  _showMessage(error.message);
                } else {
                  _showMessage('Ошибка загрузки данных Wikimapia');
                }
              }
            },
            onMarkerTap: (marker) {
              _highlightObject(markerId: marker.id);
              _openMarkerSheet(marker);
            },
            onMarkerLongPress: _openMarkerSheet,
          ),
          if (_mapAimingController.isAiming)
            const Positioned.fill(
              child: Center(child: CrosshairOverlay()),
            ),
          MapBottomDock(
            aiming: _mapAimingController.isAiming,
            leftPanel: _buildLeftPanel(),
            stats:
                TrackRecordingStatsCard(controller: _trackRecordingController),
            primaryPanel: _calibrationController.isActive
                ? CalibrationControls(
                    controller: _calibrationController, embedded: true)
                : _mapAimingController.isAiming
                    ? _buildBottomActions(context)
                    : null,
            panels: <Widget>[
              TrackRecordingControlsPanel(
                controller: _trackRecordingController,
                onStop: _stopTrackRecording,
                onCancel: _cancelTrackRecording,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _sentinelController.visible
                    ? _buildSpectralStatusChip()
                    : const SizedBox.shrink(),
              ),
            ],
            trailing: !_calibrationController.isActive &&
                    !_mapAimingController.isAiming
                ? _buildBottomActions(context)
                : null,
          ),
          if (_wikimapiaController.isLoading)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          if (_sentinelController.loading)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          _buildSearchBarrier(),
          _buildTopBar(context),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return LeftPanel(
      embedded: true,
      mapController: _mapController,
      rotation: _mapRotation,
      spectralActive: _sentinelController.visible,
      onWikimapiaPressed: _showWikimapiaUnavailable,
      onBrushPressed: _showAddActions,
      onSpectralPressed: _sentinelController.visible
          ? _sentinelController.hideImagery
          : _showSentinelCalendar,
      onSpectralLongPress: _showSentinelCalendar,
      onCenterPressed: _locationController.centerOnceOnLocation,
      onCompassPressed: _resetMapRotation,
    );
  }

  Widget _buildSpectralStatusChip() {
    return SpectralStatusChip(
      embedded: true,
      date: _sentinelController.imageryDate ?? _sentinelController.date,
      cloudCoverage: _sentinelController.imageCloudCoverage,
      loading: _sentinelController.loading,
      onEdit: _showSentinelCalendar,
      onClose: _sentinelController.hideImagery,
    );
  }

  Widget _buildSearchBarrier() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_mapSearchController.panelVisible,
        child: AnimatedOpacity(
          opacity: _mapSearchController.panelVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _mapSearchController.dismiss,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  void _showWikimapiaUnavailable() {
    _showMessage('Wikimapia пока недоступна: сервер ещё не подключён');
  }

  void _highlightObject({int? markerId, int? drawingId, int? trackId}) {
    final generation = ++_objectHighlightGeneration;
    setState(() {
      _selectedMarkerId = markerId;
      _selectedDrawingId = drawingId;
      _selectedTrackId = trackId;
    });
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted || generation != _objectHighlightGeneration) return;
      setState(() {
        _selectedMarkerId = null;
        _selectedDrawingId = null;
        _selectedTrackId = null;
      });
    });
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: Column(
        children: <Widget>[
          TopBar(
            searchController: _mapSearchController,
            onMenuPressed: () {
              _closeObjectDetailsSheets();
              _scaffoldKey.currentState?.openDrawer();
            },
            onLayersPressed: () => BaseLayerSheet.show(
              context,
              defaultSources: _defaultMapSources,
              currentLayerId: _mapLayersController.baseLayerId,
              onLayerChanged: _mapLayersController.setBaseLayer,
              currentZoom: _mapController.camera.zoom,
              onZoomClamp: () {
                final maxZoom = _baseLayerMaxZoom;
                if (_mapController.camera.zoom > maxZoom) {
                  _mapController.move(
                    _mapController.camera.center,
                    maxZoom,
                  );
                }
              },
            ),
          ),
          if (!_mapSearchController.panelVisible)
            OpacityControl(
              controller: _mapLayersController,
            ),
          SearchResultsPanel(
            controller: _mapSearchController,
            onSelected: _selectSearchResult,
          ),
          DrawingStatusBar(
            controller: _drawingController,
            onDone: _finishDrawing,
          ),
        ],
      ),
    );
  }

  void _selectSearchResult(SearchResult result) {
    _mapSearchController.selectResult(result);
    _mapController.move(result.position, 15);
  }

  Future<void> _saveCurrentDrawing() async {
    if (_drawingController.activePoints.length < 2) return;
    if ((_drawingController.mode == MapDrawingMode.polygon ||
            _drawingController.mode == MapDrawingMode.planimeter) &&
        _drawingController.activePoints.length < 3) {
      _showMessage('Минимум 3 точки для области');
      return;
    }
    final mode = _drawingController.mode;
    final typeName = switch (mode) {
      MapDrawingMode.line => 'Линия',
      MapDrawingMode.ruler => 'Линейка',
      MapDrawingMode.planimeter => 'Планиметр',
      MapDrawingMode.polygon => 'Область',
      MapDrawingMode.view => 'Объект',
    };
    final index = _mapDataController.myDrawings
            .where((item) => item.name.startsWith('$typeName '))
            .map((item) =>
                int.tryParse(item.name.substring(typeName.length + 1)) ?? 0)
            .fold<int>(0, math.max) +
        1;
    final defaultName = '$typeName $index';
    final drawing = _drawingController.finish(name: defaultName);
    if (drawing == null) return;
    final name = await DrawingSaveSheet.show(context, defaultName);
    if (!mounted) return;
    if (name == null) return; // Закрытие ввода имени не удаляет черновик.
    try {
      await _mapDataController.createDrawing(drawing.copyWith(name: name));
      _drawingController.cancel();
    } catch (_) {
      if (mounted) _showMessage('Не удалось сохранить рисунок');
    }
  }

  Future<void> _openSelectedLayerCalibration() async {
    final selected = _mapLayersController.selectedOpacityLayer;
    if (selected == null) return;
    switch (selected.kind) {
      case OpacityLayerKind.imported:
        final id = selected.importedMap?.id;
        if (id != null) await _activateMapCalibration(id);
        return;
      case OpacityLayerKind.catalog:
        final map = selected.catalogMap;
        if (map != null) {
          OffsetEditorDialog.show(
            context,
            map: map,
            onSave: (lat, lng) async {
              await _mapDataController.updateCustomMapOffset(
                map.id,
                lat,
                lng,
              );
            },
          );
        }
        return;
    }
  }

  Widget _buildBottomActions(BuildContext context) {
    return BottomActions(
      embedded: true,
      following: _locationController.followLocation,
      recording: _trackRecordingController.isRecording,
      aiming: _mapAimingController.isAiming,
      shiftEnabled: _mapLayersController.selectedOpacityLayer?.kind ==
          OpacityLayerKind.imported,
      onGpsPressed: _locationController.centerOnLocation,
      onGpsLongPress: () {
        if (!_trackRecordingController.isRecording) {
          _startTrackRecording();
          _showMessage('Запись трека начата');
        } else {
          _stopTrackRecording();
          _showMessage('Запись трека остановлена');
        }
      },
      onShiftPressed: _openSelectedLayerCalibration,
      onMapsPressed: _openMyMapsScreen,
      onAimCancel: _mapAimingController.cancelAiming,
      onAimDone: _mapAimingController.finishAiming,
    );
  }

  Future<void> _openMyMapsScreen() async {
    if (!mounted) return;
    _closeObjectDetailsSheets();
    final calibrationMapId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => MyMapsScreen(onImport: _openImportMapScreen),
      ),
    );
    if (!mounted) return;
    await _mapDataController.loadImportedMaps();
    if (!mounted || calibrationMapId == null) return;
    await _activateMapCalibration(calibrationMapId);
  }

  Future<void> _activateMapCalibration(int mapId) =>
      _calibrationController.activate(mapId);

  void _showAimingHint() {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Перемещайте карту под прицелом и нажмите «Готово»',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          backgroundColor: theme.colorScheme.surface,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _finishAimingAtCurrentCenter() {
    return _showMarkerActionsSheet(_mapController.camera.center);
  }

  String _coordinatesText(LatLng point) =>
      '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';

  Future<void> _showMarkerActionsSheet(LatLng point) async {
    if (!mounted) return;
    final action = await MarkerActionsSheet.show(context, point);
    if (!mounted || action == null) return;

    switch (action) {
      case MarkerAction.save:
        await _createNewUserMarker(point);
      case MarkerAction.share:
        try {
          await Share.share(_coordinatesText(point));
        } catch (_) {
          if (mounted) _showMessage('Не удалось открыть меню «Поделиться»');
        }
      case MarkerAction.copyCoordinates:
        if (mounted) _showMessage('Координаты скопированы');
      case MarkerAction.navigation:
        await _showNavigationChooser(point);
    }
  }

  Future<void> _showNavigationChooser(LatLng point) async {
    if (!mounted) return;
    _closeObjectDetailsSheets();
    final app = await NavigationChooserSheet.show(context);
    if (!mounted || app == null) return;

    final lat = point.latitude;
    final lng = point.longitude;
    final Uri primary;
    final Uri fallback;
    switch (app) {
      case NavigationApp.googleMaps:
        primary = Uri.parse('google.navigation:q=$lat,$lng');
        fallback = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      case NavigationApp.yandexMaps:
        primary = Uri.parse(
            'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng');
        fallback =
            Uri.parse('https://yandex.ru/maps/?rtext=~$lat,$lng&rtt=auto');
      case NavigationApp.twoGis:
        primary =
            Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat');
        fallback =
            Uri.parse('https://2gis.ru/routeSearch/rsType/car/to/$lng,$lat');
    }

    if (await canLaunchUrl(primary) &&
        await launchUrl(
          primary,
          mode: LaunchMode.externalApplication,
        )) {
      return;
    }
    try {
      if (!await launchUrl(fallback, mode: LaunchMode.externalApplication) &&
          mounted) {
        _showMessage('Навигационное приложение недоступно');
      }
    } catch (_) {
      if (mounted) _showMessage('Навигационное приложение недоступно');
    }
  }

  void _startDrawingMode(MapDrawingMode mode) {
    _mapAimingController.cancelAiming();
    _drawingController.startMode(mode);
  }

  Future<void> _showAddActions() async {
    final action = await AddActionsSheet.show(context);
    if (!mounted || action == null) return;
    switch (action) {
      case AddMapAction.marker:
        _drawingController.cancel();
        _mapAimingController.startAiming();
      case AddMapAction.line:
        _startDrawingMode(MapDrawingMode.line);
      case AddMapAction.ruler:
        _startDrawingMode(MapDrawingMode.ruler);
      case AddMapAction.planimeter:
        _startDrawingMode(MapDrawingMode.planimeter);
      case AddMapAction.recordTrack:
        _startTrackRecording();
    }
  }

  void _startTrackRecording() async {
    if (_trackRecordingController.isRecording) {
      _showMessage('Запись трека уже идёт');
      return;
    }
    await _trackRecordingController.start();
  }

  Future<void> _stopTrackRecording() async {
    final recordedTrack = await _trackRecordingController.stop();
    if (!mounted || recordedTrack == null) return;
    final defaultName =
        'Трек от ${DateFormat('dd.MM.yyyy').format(DateTime.now())}';
    final selection = await TrackBottomSheet.showSave(
      context,
      defaultName: defaultName,
    );
    if (!mounted) return;
    if (selection != null) {
      await _mapDataController.createTrack(
        recordedTrack.copyWith(
          name: selection.name,
          color: selection.color,
          visible: true,
        ),
      );
      if (mounted) _showMessage('Трек сохранён');
    }
  }

  Future<void> _cancelTrackRecording() async {
    await _trackRecordingController.cancel();
  }

  Future<void> _exportTrack(Track track) async {
    try {
      final path = await GpxExporter.exportTrack(track);
      _showMessage('Трек экспортирован в $path');
    } catch (e) {
      _showMessage('Ошибка экспорта: $e');
    }
  }

  Future<void> _openMyObjectsScreen() async {
    if (!mounted) return;
    _closeObjectDetailsSheets();
    final target = await Navigator.of(context).push<MapObjectTarget>(
      MaterialPageRoute<MapObjectTarget>(
        builder: (_) => MyObjectsScreen(dataController: _mapDataController),
      ),
    );
    if (!mounted || target == null) return;
    await _focusMapObject(target);
  }

  Future<void> _focusMapObject(MapObjectTarget target) async {
    LatLng? point;
    UserMarker? marker;
    Drawing? drawing;
    Track? track;
    switch (target.type) {
      case MapObjectType.marker:
        for (final item in _mapDataController.myMarkers) {
          if (item.id == target.id) {
            marker = item;
            point = item.point;
            break;
          }
        }
      case MapObjectType.drawing:
        for (final item in _mapDataController.myDrawings) {
          if (item.id == target.id && item.points.isNotEmpty) {
            drawing = item;
            point = _objectCenter(item.points);
            break;
          }
        }
      case MapObjectType.track:
        for (final item in _mapDataController.myTracks) {
          if (item.id == target.id && item.points.isNotEmpty) {
            track = item;
            point = _objectCenter(item.points);
            break;
          }
        }
    }
    if (point == null) return;

    if (marker != null) {
      setState(() {
        _selectedMarkerId = marker!.id;
        _selectedDrawingId = null;
      });
    } else if (drawing != null) {
      setState(() {
        _selectedDrawingId = drawing!.id;
        _selectedMarkerId = null;
        _selectedTrackId = null;
      });
    } else if (track != null) {
      setState(() {
        _selectedTrackId = track!.id;
        _selectedMarkerId = null;
        _selectedDrawingId = null;
      });
    }
    await _animateMapTo(point, target.type == MapObjectType.marker ? 16 : 15);
    if (!mounted) return;
    if (marker != null) {
      _openMarkerSheet(marker);
    } else if (drawing != null) {
      _openDrawingSheet(drawing);
    } else if (track != null) {
      _openTrackSheet(track);
    }
  }

  LatLng _objectCenter(List<LatLng> points) {
    final latitude =
        points.fold<double>(0, (sum, point) => sum + point.latitude) /
            points.length;
    final longitude =
        points.fold<double>(0, (sum, point) => sum + point.longitude) /
            points.length;
    return LatLng(latitude, longitude);
  }

  Future<void> _animateMapTo(LatLng target, double targetZoom) async {
    final start = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    const steps = 18;
    for (var step = 1; step <= steps; step++) {
      if (!mounted) return;
      final progress = Curves.easeInOut.transform(step / steps);
      _mapController.move(
        LatLng(
          start.latitude + (target.latitude - start.latitude) * progress,
          start.longitude + (target.longitude - start.longitude) * progress,
        ),
        startZoom + (targetZoom - startZoom) * progress,
      );
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
  }

  Future<void> _openImportMapScreen() async {
    if (!mounted) return;
    _closeObjectDetailsSheets();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ImportMapScreen(
          currentMapCenter: _mapController.camera.center,
          onImported: _mapDataController.loadImportedMaps,
        ),
      ),
    );
    if (mounted) {
      await _mapDataController.loadImportedMaps();
      await _mapDataController.loadCustomMaps();
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMapTap(LatLng point) async {
    if (_wikimapiaController.activeId != null) {
      _wikimapiaController.setActiveId('');
    }
    if (_drawingController.isActive) {
      if (_drawingController.handleDrawingTap(point)) {
        await _finishDrawing();
      }
      return;
    }
    final hit = _mapInteractionController.hitTest(
      point: point,
      tracks: _mapDataController.myTracks,
      drawings: _mapDataController.myDrawings,
      camera: _mapController.camera,
    );
    if (hit?.track case final track?) {
      _highlightObject(trackId: track.id);
      _objectPreview.toggle(ObjectPreview(
        id: 'track-${track.id}',
        point: point,
        child: ObjectPreviewCard(
          leading: Icon(Icons.route, size: 22, color: Color(track.color)),
          title: track.name,
          subtitle: MeasurementUtils.formatDistance(track.distance,
              metric: _metricUnits),
          onClose: _objectPreview.hide,
          onTap: () {
            _objectPreview.hide();
            _openTrackSheet(track);
          },
        ),
      ));
      return;
    }
    if (hit?.drawing case final drawing?) {
      _highlightObject(drawingId: drawing.id);
      _objectPreview.toggle(ObjectPreview(
        id: 'drawing-${drawing.id}',
        point: point,
        child: ObjectPreviewCard(
          leading: Icon(
              drawing.category == 'measurement'
                  ? Icons.straighten
                  : Icons.gesture,
              size: 22,
              color: Color(drawing.color)),
          title: drawing.name,
          subtitle: MeasurementUtils.formatMeasurement(drawing, _metricUnits),
          onClose: _objectPreview.hide,
          onTap: () {
            _objectPreview.hide();
            _openDrawingSheet(drawing);
          },
        ),
      ));
      return;
    }
    _closeObjectDetailsSheets();
    if (_selectedDrawingId != null ||
        _selectedMarkerId != null ||
        _selectedTrackId != null) {
      setState(() {
        _selectedDrawingId = null;
        _selectedMarkerId = null;
        _selectedTrackId = null;
      });
    }
    if (_mapSearchController.panelVisible) {
      _mapSearchController.dismiss();
    }
  }

  void _scheduleSentinelRefresh() {
    _sentinelController.scheduleRefresh();
  }

  void _scheduleWikimapiaRefresh(LatLngBounds bounds) {
    _wikimapiaController.scheduleLoad(bounds);
  }

  void _handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) _locationController.onUserGesture();
    _locationController.onCameraChanged(camera, hasGesture: hasGesture);
    _scheduleWikimapiaRefresh(camera.visibleBounds);
    if (hasGesture) _scheduleSentinelRefresh();
  }

  Future<void> _showSentinelCalendar() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final dates = await _sentinelController.loadDatesForVisibleArea();
    if (!mounted) return;
    Navigator.pop(context);
    if (dates.isEmpty) {
      _showMessage('Нет доступных снимков в этой области');
      return;
    }
    final cloudByDate = <DateTime, double>{};
    for (final d in dates) {
      final dt = d.date;
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final prev = cloudByDate[day];
      if (prev == null || d.cloudCover < prev) {
        cloudByDate[day] = d.cloudCover;
      }
    }
    final selection = await SentinelCalendarDialog.show(
      context,
      cloudByDate: cloudByDate,
      initialDate: _sentinelController.date,
      initialCloudCoverage: _sentinelController.cloudCoverage,
    );
    if (!mounted || selection == null) return;
    await _sentinelController.applyDate(
      selection.date,
      maxCloudCoverage: selection.maxCloudCoverage,
      imageCloudCoverage: selection.imageCloudCoverage,
    );
  }

  Future<void> _finishDrawing() async {
    if (!_drawingController.isActive ||
        _drawingController.activePoints.length < 2) {
      return;
    }
    if ((_drawingController.mode == MapDrawingMode.polygon ||
            _drawingController.mode == MapDrawingMode.planimeter) &&
        _drawingController.activePoints.length < 3) {
      _showMessage('Минимум 3 точки для области');
      return;
    }
    await _saveCurrentDrawing();
  }

  Future<void> _createNewUserMarker(LatLng point) async {
    if (!mounted) return;
    final selection = await MarkerCreateDialog.show(
      context,
      point: point,
      previewBuilder: (shape, colorHex, size) => MarkerMapPreview(
        point: point,
        shape: shape,
        colorHex: colorHex,
        size: size,
      ),
    );
    if (!mounted || selection == null) return;
    final marker = UserMarker(
      name: selection.name,
      description: selection.description,
      lat: point.latitude,
      lng: point.longitude,
      colorHex: selection.colorHex,
      shape: selection.shape,
      size: selection.size,
      group: selection.group,
      media: selection.media,
    );
    try {
      await _mapDataController.createMarker(marker);
      if (mounted) _showMessage('Метка сохранена');
    } catch (_) {
      if (mounted) _showMessage('Не удалось сохранить метку');
    }
  }

  Future<bool> _confirmDeleteMarker(UserMarker marker) async {
    if (!mounted) return false;
    final confirmed = await confirmObjectDelete(
      context,
      type: 'метку',
      name: marker.name,
    );
    if (!mounted || !confirmed) return false;
    await _mapDataController.deleteMarker(marker.id!);
    if (mounted) setState(() => _selectedMarkerId = null);
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    AppNotifications.message(context, message);
  }

  Future<void> _openMarkerSheet(UserMarker marker) async {
    if (!mounted) return;
    _objectModalSheetOpen = true;
    try {
      final updated = await MarkerBottomSheet.show(
        context,
        marker: marker,
        onDelete: _confirmDeleteMarker,
        onStyle: (current) async {
          final selection = await MarkerStylePickerSheet.show(
            context,
            point: current.point,
            initialShape: current.shape,
            initialColor: current.colorHex,
            initialSize: current.size,
            previewBuilder: (shape, colorHex, size) => MarkerMapPreview(
              point: current.point,
              shape: shape,
              colorHex: colorHex,
              size: size,
            ),
          );
          if (selection == null) return null;
          return current.copyWith(
            shape: selection.shape,
            colorHex: selection.colorHex,
            size: selection.size,
          );
        },
        onShare: () => Share.share('${marker.lat}, ${marker.lng}'),
        onExport: () => _showMessage('В разработке'),
        onCopyCoordinates: () async {
          await Clipboard.setData(
            ClipboardData(text: '${marker.lat}, ${marker.lng}'),
          );
          if (mounted) _showMessage('Координаты скопированы');
        },
        onNavigation: () => _showNavigationChooser(marker.point),
        onDirection: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DirectionScreen(lat: marker.lat, lng: marker.lng),
            ),
          );
        },
      );
      if (!mounted || updated == null) return;
      await _mapDataController.updateMarker(updated);
    } finally {
      _objectModalSheetOpen = false;
    }
  }

  Future<void> _openDrawingSheet(Drawing drawing) async {
    if (!mounted) return;
    _objectModalSheetOpen = true;
    try {
      final updated = await DrawingBottomSheet.show(
        context,
        drawing: drawing,
        typeLabel: _drawingTypeLabel(drawing),
        valueLabel: _drawingValue(drawing),
        onDelete: _confirmDeleteDrawing,
        onShare: () => Share.share(
          '${drawing.name}\n${_drawingValue(drawing)}\n'
          '${drawing.points.map((point) => '${point.latitude}, ${point.longitude}').join('\n')}',
        ),
        onCopyCoordinates: () async {
          final center = _objectCenter(drawing.points);
          await Clipboard.setData(
            ClipboardData(text: '${center.latitude}, ${center.longitude}'),
          );
          if (mounted) _showMessage('Координаты скопированы');
        },
        onNavigation: () =>
            _showNavigationChooser(_objectCenter(drawing.points)),
      );
      if (!mounted || updated == null) return;
      await _mapDataController.updateDrawing(updated);
    } finally {
      _objectModalSheetOpen = false;
    }
  }

  Future<void> _openTrackSheet(Track track) async {
    if (!mounted) return;
    _objectModalSheetOpen = true;
    try {
      final updated = await TrackBottomSheet.show(
        context,
        track: track,
        onDelete: _confirmDeleteTrack,
        onHistory: () => TrackHistorySheet.show(context, track),
        onShare: () => _exportTrack(track),
        onNavigation: () => _showNavigationChooser(track.points.first),
      );
      if (!mounted || updated == null) return;
      await _mapDataController.updateTrack(updated);
    } finally {
      _objectModalSheetOpen = false;
    }
  }

  Future<bool> _confirmDeleteDrawing(Drawing drawing) async {
    if (!mounted) return false;
    final confirmed = await confirmObjectDelete(
      context,
      type: drawing.category != 'measurement'
          ? 'рисунок'
          : drawing.type == 'line'
              ? 'линейку'
              : 'измерение',
      name: drawing.name,
    );
    if (!mounted || !confirmed) return false;
    await _mapDataController.deleteDrawing(drawing.id!);
    if (_selectedDrawingId == drawing.id && mounted) {
      setState(() => _selectedDrawingId = null);
    }
    return true;
  }

  String _drawingTypeLabel(Drawing drawing) {
    if (drawing.type == 'polygon' && drawing.category == 'measurement') {
      return 'Планиметр';
    }
    return drawing.category == 'measurement' ? 'Линейка' : 'Линия';
  }

  String _drawingValue(Drawing drawing) {
    if (drawing.type != 'polygon') {
      return MeasurementUtils.formatDistance(
        MeasurementUtils.totalDistance(drawing.points),
        metric: _metricUnits,
      );
    }
    final closed = [...drawing.points, drawing.points.first];
    final area = MeasurementUtils.formatArea(
      MeasurementUtils.calculateArea(drawing.points),
      metric: _metricUnits,
    );
    final perimeter = MeasurementUtils.formatDistance(
      MeasurementUtils.totalDistance(closed),
      metric: _metricUnits,
    );
    return 'Площадь: $area · Периметр: $perimeter';
  }

  Future<bool> _confirmDeleteTrack(Track track) async {
    if (!mounted || track.id == null) return false;
    final confirmed = await confirmObjectDelete(
      context,
      type: 'трек',
      name: track.name,
    );
    if (!mounted || !confirmed) return false;
    await _mapDataController.deleteTrack(track.id!);
    if (mounted) setState(() => _selectedTrackId = null);
    return true;
  }
}
