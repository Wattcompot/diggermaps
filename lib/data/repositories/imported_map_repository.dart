import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/imported_map.dart';

/// Manages persistence for [ImportedMap] rows.
///
/// Every mutation broadcasts an invalidation event so that [watchAll] streams
/// across different instances / widgets pick up changes immediately.
class ImportedMapRepository {
  final AppDatabase _db = AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // Broadcast invalidation hub.
  // ---------------------------------------------------------------------------
  static final StreamController<void> _invalidateController =
      StreamController<void>.broadcast();

  /// Shared stream that fires whenever data changes (save, update, delete).
  /// All [watchAll] calls listen to this controller, then reload from DB.
  static Stream<void> get onChanged => _invalidateController.stream;

  static void _notify() {
    // Fire-and-forget; broadcast stream handles multiple listeners.
    _invalidateController.add(null);
  }

  // ---------------------------------------------------------------------------
  // Save.
  // ---------------------------------------------------------------------------

  /// Inserts a new row.
  ///
  /// New-style parameters ([mapFilePath], [imageFilePath], [format],
  /// [boundsJson], [calibrationPointsJson], [offsetX], [offsetY], [opacity])
  /// are preferred. For backward compatibility the legacy [path] / [type] /
  /// [bounds] triplet is also accepted and mapped onto the new columns.
  Future<void> save({
    required String name,

    // -- new-style ------------------------------------------------------------
    String? mapFilePath,
    String? imageFilePath,
    String? format,
    String? boundsJson,
    String? calibrationPointsJson,
    double offsetX = 0,
    double offsetY = 0,
    double opacity = 0.7,
    bool visible = true,

    // -- legacy (backward-compatible) -----------------------------------------
    String? path,
    String? type,
    String? bounds,
    int? minZoom,
    int? maxZoom,
  }) async {
    if (kIsWeb) return;

    // Resolve format: new-style wins, then legacy type, then default.
    final resolvedFormat = format ?? type ?? 'raster';

    // Resolve mapFilePath: explicit new-style, or legacy path when it ends
    // with .map.
    String? resolvedMapFilePath = mapFilePath;
    if (resolvedMapFilePath == null && path != null && path.endsWith('.map')) {
      resolvedMapFilePath = path;
    }

    // Resolve imageFilePath: explicit new-style, or legacy path for non-.map.
    String? resolvedImageFilePath = imageFilePath;
    if (resolvedImageFilePath == null &&
        path != null &&
        !path.endsWith('.map')) {
      resolvedImageFilePath = path;
    }
    // Also accept explicit imageFilePath even if not provided.
    if (resolvedImageFilePath == null && imageFilePath != null) {
      resolvedImageFilePath = imageFilePath;
    }

    // Resolve bounds JSON: new-style wins, then legacy.
    final resolvedBoundsJson = boundsJson ?? bounds;

    final db = await _db.database;
    await db.insert('imported_maps', {
      'name': name,
      'map_file_path': resolvedMapFilePath,
      'image_file_path': resolvedImageFilePath,
      'format': resolvedFormat,
      'bounds_json': resolvedBoundsJson,
      'calibration_points_json': calibrationPointsJson,
      'offset_x': offsetX,
      'offset_y': offsetY,
      'opacity': opacity,
      'visible': visible ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
      // Keep legacy columns populated so old consumers don't break.
      'path': path ?? resolvedImageFilePath ?? resolvedMapFilePath,
      'type': resolvedFormat,
      'bounds': resolvedBoundsJson,
      if (minZoom != null) 'min_zoom': minZoom,
      if (maxZoom != null) 'max_zoom': maxZoom,
    });

    _notify();
  }

  // ---------------------------------------------------------------------------
  // Queries.
  // ---------------------------------------------------------------------------

  /// Returns all rows ordered by creation date (newest first).
  Future<List<ImportedMap>> getAll() async {
    if (kIsWeb) return [];
    final db = await _db.database;
    final rows = await db.query(
      'imported_maps',
      orderBy: 'created_at DESC',
    );
    return rows.map(ImportedMap.fromMap).toList();
  }

  /// A reactive stream that reloads the full list on every mutation.
  ///
  /// Uses the shared broadcast invalidation hub so that multiple listeners
  /// (widgets, other repository instances) all see the same updates.
  Stream<List<ImportedMap>> watchAll() async* {
    yield await getAll();
    yield* onChanged.asyncMap((_) => getAll());
  }

  // ---------------------------------------------------------------------------
  // Partial updates.
  // ---------------------------------------------------------------------------

  Future<void> updateName(int id, String name) async {
    if (kIsWeb) return;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    final db = await _db.database;
    await db.update(
      'imported_maps',
      {'name': trimmedName},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> updateVisibility(int id, bool visible) async {
    if (kIsWeb) return;
    final db = await _db.database;
    await db.update(
      'imported_maps',
      {'visible': visible ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> updateOpacity(int id, double opacity) async {
    if (kIsWeb) return;
    final db = await _db.database;
    await db.update(
      'imported_maps',
      {'opacity': opacity.clamp(0.0, 1.0)},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  Future<void> updateOffset(int id, double offsetX, double offsetY) async {
    if (kIsWeb) return;
    final db = await _db.database;
    await db.update(
      'imported_maps',
      {'offset_x': offsetX, 'offset_y': offsetY},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Delete.
  // ---------------------------------------------------------------------------

  Future<void> delete(int id) async {
    if (kIsWeb) return;
    final db = await _db.database;
    await db.delete(
      'imported_maps',
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }
}
