import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/imported_map.dart';
import '../../data/repositories/custom_map_repository.dart';
import '../../data/repositories/imported_map_repository.dart';

enum OpacityLayerKind { imported, catalog }

@immutable
class OpacityLayerSelection {
  const OpacityLayerSelection.imported(this.importedMap)
      : kind = OpacityLayerKind.imported,
        catalogMap = null;

  const OpacityLayerSelection.catalog(this.catalogMap)
      : kind = OpacityLayerKind.catalog,
        importedMap = null;

  final OpacityLayerKind kind;
  final ImportedMap? importedMap;
  final CustomMapLayer? catalogMap;

  String get key => kind == OpacityLayerKind.imported
      ? 'imported:${importedMap!.id}'
      : 'catalog:${catalogMap!.id}';
  String get name => importedMap?.name ?? catalogMap!.name;
  double get opacity => importedMap?.opacity ?? catalogMap!.opacity;
}

class MapLayersController extends ChangeNotifier {
  MapLayersController({
    ImportedMapRepository? importedMapRepository,
    CustomMapRepository? customMapRepository,
  })  : _importedMapRepository =
            importedMapRepository ?? ImportedMapRepository(),
        _customMapRepository = customMapRepository ?? CustomMapRepository();

  final ImportedMapRepository _importedMapRepository;
  final CustomMapRepository _customMapRepository;

  String _baseLayerId = 'esri_world_imagery';
  final Set<String> _enabledCustomMapIds = <String>{};
  String? _activeOpacityLayerKey;
  bool _opacitySelectorOpen = false;
  int? _activeImportedMapId;
  bool _showSpectral = false;
  String? _spectralTileUrl;
  bool _spectralLoading = false;
  bool _showWikimapia = false;
  List<CustomMapLayer> _customMaps = const <CustomMapLayer>[];
  List<ImportedMap> _importedMaps = const <ImportedMap>[];
  StreamSubscription<List<ImportedMap>>? _importedMapsSubscription;

  String get baseLayerId => _baseLayerId;
  Set<String> get enabledCustomMapIds =>
      Set<String>.unmodifiable(_enabledCustomMapIds);
  String? get activeOpacityLayerKey => _activeOpacityLayerKey;
  bool get opacitySelectorOpen => _opacitySelectorOpen;
  int? get activeImportedMapId => _activeImportedMapId;
  bool get showSpectral => _showSpectral;
  String? get spectralTileUrl => _spectralTileUrl;
  bool get spectralLoading => _spectralLoading;
  bool get showWikimapia => _showWikimapia;
  List<CustomMapLayer> get customMaps => _customMaps;
  List<ImportedMap> get importedMaps => _importedMaps;

  List<OpacityLayerSelection> get activeOpacityLayers =>
      <OpacityLayerSelection>[
        ..._importedMaps
            .where((map) => map.visible && map.isRasterOverlay)
            .map(OpacityLayerSelection.imported),
        ..._customMaps
            .where((map) =>
                _enabledCustomMapIds.contains(map.id) && map.isRenderable)
            .map(OpacityLayerSelection.catalog),
      ];

  OpacityLayerSelection? get selectedOpacityLayer {
    final layers = activeOpacityLayers;
    if (layers.isEmpty) return null;
    return layers.firstWhere(
      (layer) => layer.key == _activeOpacityLayerKey,
      orElse: () => layers.first,
    );
  }

  void setBaseLayer(String value) {
    if (_baseLayerId == value) return;
    _baseLayerId = value;
    notifyListeners();
  }

  void toggleCustomMap(String id) {
    if (!_enabledCustomMapIds.remove(id)) _enabledCustomMapIds.add(id);
    _syncOpacitySelection();
    notifyListeners();
  }

  void setCustomMaps(List<CustomMapLayer> maps) {
    _customMaps = List<CustomMapLayer>.unmodifiable(maps);
    _enabledCustomMapIds
      ..clear()
      ..addAll(maps.where((map) => map.enabled).map((map) => map.id));
    _syncOpacitySelection();
    notifyListeners();
  }

  void setImportedMaps(List<ImportedMap> maps) {
    _importedMaps = List<ImportedMap>.unmodifiable(maps);
    if (_activeImportedMapId == null ||
        !maps.any((map) =>
            map.id == _activeImportedMapId &&
            map.visible &&
            map.isRasterOverlay)) {
      final visible = maps.where((map) => map.visible && map.isRasterOverlay);
      _activeImportedMapId = visible.isEmpty ? null : visible.first.id;
    }
    _syncOpacitySelection();
    notifyListeners();
  }

  void watchImportedMaps() {
    _importedMapsSubscription?.cancel();
    _importedMapsSubscription = _importedMapRepository.watchAll().listen(
          setImportedMaps,
        );
  }

  void setOpacitySelectorOpen(bool value) {
    if (_opacitySelectorOpen == value) return;
    _opacitySelectorOpen = value;
    notifyListeners();
  }

  void selectOpacityLayer(String key) {
    _activeOpacityLayerKey = key;
    final selected =
        activeOpacityLayers.where((layer) => layer.key == key).firstOrNull;
    if (selected?.importedMap?.id != null) {
      _activeImportedMapId = selected!.importedMap!.id;
    }
    _opacitySelectorOpen = false;
    notifyListeners();
  }

  Future<void> updateOpacity(
    OpacityLayerSelection layer,
    double opacity,
  ) async {
    switch (layer.kind) {
      case OpacityLayerKind.imported:
        final map = layer.importedMap!;
        if (map.id == null) return;
        _importedMaps = _importedMaps
            .map((item) =>
                item.id == map.id ? item.copyWith(opacity: opacity) : item)
            .toList(growable: false);
        notifyListeners();
        await _importedMapRepository.updateOpacity(map.id!, opacity);
      case OpacityLayerKind.catalog:
        final map = layer.catalogMap!;
        _customMaps = _customMaps
            .map((item) =>
                item.id == map.id ? item.copyWith(opacity: opacity) : item)
            .toList(growable: false);
        notifyListeners();
        await _customMapRepository.updateOpacity(map.id, opacity);
    }
  }

  void toggleSpectral() {
    _showSpectral = !_showSpectral;
    notifyListeners();
  }

  void setSpectral({
    required bool visible,
    String? tileUrl,
    required bool loading,
  }) {
    _showSpectral = visible;
    _spectralTileUrl = tileUrl;
    _spectralLoading = loading;
    notifyListeners();
  }

  void toggleWikimapia() {
    _showWikimapia = !_showWikimapia;
    notifyListeners();
  }

  void setWikimapia(bool value) {
    _showWikimapia = value;
    notifyListeners();
  }

  void _syncOpacitySelection() {
    final layers = activeOpacityLayers;
    if (layers.isEmpty) {
      _activeOpacityLayerKey = null;
    } else if (!layers.any((layer) => layer.key == _activeOpacityLayerKey)) {
      _activeOpacityLayerKey = layers.first.key;
    }
  }

  @override
  void dispose() {
    _importedMapsSubscription?.cancel();
    super.dispose();
  }
}
