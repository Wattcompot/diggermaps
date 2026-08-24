import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../data/models/imported_map.dart';
import '../../data/repositories/imported_map_repository.dart';
import 'map_layers_controller.dart';

class MapCalibrationController extends ChangeNotifier {
  MapCalibrationController({
    required MapController mapController,
    required MapLayersController layersController,
    required ImportedMapRepository importedMapRepository,
  })  : _mapController = mapController,
        _layersController = layersController,
        _importedMapRepository = importedMapRepository;

  final MapController _mapController;
  final MapLayersController _layersController;
  final ImportedMapRepository _importedMapRepository;

  int? _activeCalibrationMapId;
  int _calibrationStepMeters = 10;

  int? get activeCalibrationMapId => _activeCalibrationMapId;
  int get calibrationStepMeters => _calibrationStepMeters;
  bool get isActive => activeCalibrationMap != null;

  ImportedMap? get activeCalibrationMap {
    for (final map in _layersController.importedMaps) {
      if (map.id == _activeCalibrationMapId && map.isRasterOverlay) return map;
    }
    return null;
  }

  Future<void> activate(int mapId) async {
    ImportedMap? selectedMap;
    for (final map in _layersController.importedMaps) {
      if (map.id == mapId && map.isRasterOverlay) {
        selectedMap = map;
        break;
      }
    }
    if (selectedMap == null) return;

    if (!selectedMap.visible) {
      _replaceImportedMap(selectedMap.copyWith(visible: true));
      await _importedMapRepository.updateVisibility(mapId, true);
    }
    _activeCalibrationMapId = mapId;
    notifyListeners();
  }

  void syncImportedMaps() {
    if (_activeCalibrationMapId != null && activeCalibrationMap == null) {
      _activeCalibrationMapId = null;
      notifyListeners();
    }
  }

  void setStepMeters(int value) {
    if (_calibrationStepMeters == value) return;
    _calibrationStepMeters = value;
    notifyListeners();
  }

  void shiftActiveMap(int xDirection, int yDirection) {
    final map = activeCalibrationMap;
    if (map?.id == null) return;
    final bounds = map!.parsedBounds;
    final latitude = bounds == null
        ? _mapController.camera.center.latitude
        : (bounds['minLat']! + bounds['maxLat']!) / 2 + map.offsetY;
    const latitudeMetersPerDegree = 111320.0;
    final longitudeMetersPerDegree = math.max(
      1.0,
      latitudeMetersPerDegree * math.cos(latitude * math.pi / 180).abs(),
    );
    final updated = map.copyWith(
      offsetX: map.offsetX +
          xDirection * _calibrationStepMeters / longitudeMetersPerDegree,
      offsetY: map.offsetY +
          yDirection * _calibrationStepMeters / latitudeMetersPerDegree,
    );
    _replaceImportedMap(updated);
    _importedMapRepository.updateOffset(
      map.id!,
      updated.offsetX,
      updated.offsetY,
    );
  }

  void resetActiveMapOffset() {
    final map = activeCalibrationMap;
    if (map?.id == null) return;
    final updated = map!.copyWith(offsetX: 0, offsetY: 0);
    _replaceImportedMap(updated);
    _importedMapRepository.updateOffset(map.id!, 0, 0);
  }

  void finish() {
    if (_activeCalibrationMapId == null) return;
    _activeCalibrationMapId = null;
    notifyListeners();
  }

  void _replaceImportedMap(ImportedMap updated) {
    final maps = List<ImportedMap>.from(_layersController.importedMaps);
    final index = maps.indexWhere((map) => map.id == updated.id);
    if (index < 0) return;
    maps[index] = updated;
    _layersController.setImportedMaps(maps);
  }
}
