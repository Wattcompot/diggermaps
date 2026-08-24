import 'package:flutter/foundation.dart';

import '../../core/map_formats/imported_vector_parser.dart';
import '../../data/models/drawing.dart';
import '../../data/models/track.dart';
import '../../data/models/user_marker.dart';
import '../../data/repositories/custom_map_repository.dart';
import '../../data/repositories/drawing_repository.dart';
import '../../data/repositories/imported_map_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/repositories/user_marker_repository.dart';
import 'map_layers_controller.dart';

class MapDataController extends ChangeNotifier {
  MapDataController({
    required MapLayersController layersController,
    CustomMapRepository? customMapRepository,
    UserMarkerRepository? userMarkerRepository,
    DrawingRepository? drawingRepository,
    TrackRepository? trackRepository,
    ImportedMapRepository? importedMapRepository,
  })  : _customMapRepository = customMapRepository ?? CustomMapRepository(),
        _userMarkerRepository = userMarkerRepository ?? UserMarkerRepository(),
        _drawingRepository = drawingRepository ?? DrawingRepository(),
        _trackRepository = trackRepository ?? TrackRepository(),
        _importedMapRepository =
            importedMapRepository ?? ImportedMapRepository(),
        _layersController = layersController;

  final CustomMapRepository _customMapRepository;
  final UserMarkerRepository _userMarkerRepository;
  final DrawingRepository _drawingRepository;
  final TrackRepository _trackRepository;
  final ImportedMapRepository _importedMapRepository;
  final MapLayersController _layersController;

  final Map<String, List<ImportedVectorGeometry>> _importedVectors = {};
  List<UserMarker> _myMarkers = const <UserMarker>[];
  List<Drawing> _myDrawings = const <Drawing>[];
  final List<Drawing> _temporaryDrawings = <Drawing>[];
  List<Track> _myTracks = const <Track>[];

  Map<String, List<ImportedVectorGeometry>> get importedVectors =>
      Map<String, List<ImportedVectorGeometry>>.unmodifiable(_importedVectors);
  List<UserMarker> get myMarkers => _myMarkers;
  List<Drawing> get myDrawings => _myDrawings;
  List<Drawing> get temporaryDrawings => _temporaryDrawings;
  List<Track> get myTracks => _myTracks;

  Future<void> loadAll() => Future.wait<void>([
        loadCustomMaps(),
        loadUserMarkers(),
        loadDrawings(),
        loadTracks(),
        loadImportedMaps(),
      ]);

  Future<void> loadCustomMaps() async {
    final maps = await _customMapRepository.loadMaps();
    for (final map in maps) {
      if ((map.sourceType == MapSourceType.kml ||
              map.sourceType == MapSourceType.kmz ||
              map.sourceType == MapSourceType.gpx) &&
          !_importedVectors.containsKey(map.urlTemplate)) {
        try {
          _importedVectors[map.urlTemplate] =
              await ImportedVectorParser.parse(map.urlTemplate);
        } catch (_) {
          _importedVectors[map.urlTemplate] = const [];
        }
      }
    }
    _layersController.setCustomMaps(maps);
    notifyListeners();
  }

  Future<void> loadUserMarkers() async {
    _myMarkers = List<UserMarker>.unmodifiable(
      await _userMarkerRepository.getAll(),
    );
    notifyListeners();
  }

  Future<void> loadDrawings() async {
    _myDrawings = List<Drawing>.unmodifiable(await _drawingRepository.getAll());
    notifyListeners();
  }

  Future<void> loadTracks() async {
    _myTracks = List<Track>.unmodifiable(await _trackRepository.getAll());
    notifyListeners();
  }

  Future<void> loadImportedMaps() async {
    _layersController.setImportedMaps(await _importedMapRepository.getAll());
  }

  Future<int> createMarker(UserMarker marker) async {
    final id = await _userMarkerRepository.create(marker);
    await loadUserMarkers();
    return id;
  }

  Future<void> updateMarker(UserMarker marker) async {
    await _userMarkerRepository.update(marker);
    await loadUserMarkers();
  }

  Future<void> deleteMarker(int id) async {
    await _userMarkerRepository.delete(id);
    await loadUserMarkers();
  }

  Future<int> createDrawing(Drawing drawing) async {
    final id = await _drawingRepository.create(drawing);
    await loadDrawings();
    return id;
  }

  Future<void> updateDrawing(Drawing drawing) async {
    await _drawingRepository.update(drawing);
    await loadDrawings();
  }

  Future<void> deleteDrawing(int id) async {
    await _drawingRepository.delete(id);
    await loadDrawings();
  }

  Future<int> createTrack(Track track) async {
    final id = await _trackRepository.create(track);
    await loadTracks();
    return id;
  }

  Future<void> updateTrack(Track track) async {
    await _trackRepository.update(track);
    await loadTracks();
  }

  Future<void> deleteTrack(int id) async {
    await _trackRepository.delete(id);
    await loadTracks();
  }

  Future<void> updateCustomMapOffset(
    String id,
    double latitudeOffset,
    double longitudeOffset,
  ) async {
    await _customMapRepository.updateOffset(
      id,
      latitudeOffset,
      longitudeOffset,
    );
    await loadCustomMaps();
  }
}
