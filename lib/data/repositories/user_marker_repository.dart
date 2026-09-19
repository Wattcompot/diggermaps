import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/user_marker.dart';
import '../../services/media/marker_media_store.dart';
import 'marker_json_store.dart';

class UserMarkerRepository {
  UserMarkerRepository({
    Database? database,
    MarkerJsonStore? jsonStore,
    MarkerMediaStore? mediaStore,
  })  : _database = database,
        _mediaStore = mediaStore ?? MarkerMediaStore(),
        _jsonStore = jsonStore ??
            (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.windows &&
                    database == null
                ? MarkerJsonStore()
                : null);

  final Database? _database;
  final MarkerMediaStore _mediaStore;
  final MarkerJsonStore? _jsonStore;
  static final List<UserMarker> _webItems = [];
  static int _webId = 0;

  Future<Database> get _db async =>
      _database ?? await AppDatabase.instance.database;

  Future<String> _markerTable(Database db) async {
    final tables = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: const ['table', 'markers'],
      limit: 1,
    );
    return tables.isNotEmpty ? 'markers' : 'user_markers';
  }

  Map<String, dynamic> _values(UserMarker marker, String table) {
    final values = marker.toMap()..remove('id');
    if (table != 'markers') return values;
    return {
      'name': marker.name,
      'lat': marker.lat,
      'lng': marker.lng,
      'desc': marker.description,
      'icon': marker.shape,
      'color': marker.colorHex,
      'group': marker.group,
      'createdAt': marker.createdAt.toIso8601String(),
      'visible': marker.visible ? 1 : 0,
      'media_json': values['media_json'],
    };
  }

  Future<int> create(UserMarker marker) async {
    if (kIsWeb) {
      final id = ++_webId;
      _webItems.add(marker.copyWith(id: id));
      return id;
    }
    // A local variable keeps the non-null type usable inside the closure: the
    // field itself cannot be promoted at the package language version.
    final jsonStore = _jsonStore;
    if (jsonStore != null) {
      return jsonStore.access((items) async {
        final id = items.fold<int>(
                0, (max, item) => (item.id ?? 0) > max ? item.id! : max) +
            1;
        items.add(marker.copyWith(id: id));
        return id;
      }, write: true);
    }
    final db = await _db;
    final table = await _markerTable(db);
    return db.insert(table, _values(marker, table));
  }

  Future<UserMarker?> read(int id) async {
    if (kIsWeb || _jsonStore != null) {
      for (final marker in await getAll()) {
        if (marker.id == id) return marker;
      }
      return null;
    }
    final db = await _db;
    final maps = await db
        .query(await _markerTable(db), where: 'id = ?', whereArgs: [id]);
    return maps.isEmpty ? null : UserMarker.fromMap(maps.first);
  }

  Future<List<UserMarker>> getAll() async {
    if (kIsWeb) return List.unmodifiable(_webItems.reversed);
    final jsonStore = _jsonStore;
    if (jsonStore != null) {
      return jsonStore.access((items) async =>
          items..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }
    final db = await _db;
    final table = await _markerTable(db);
    final createdAtColumn = table == 'markers' ? 'createdAt' : 'created_at';
    final result = await db.query(table, orderBy: '$createdAtColumn DESC');
    return result.map(UserMarker.fromMap).toList();
  }

  Future<int> update(UserMarker marker) async {
    if (marker.id == null) return 0;
    final previous = await read(marker.id!);
    final int count;
    if (kIsWeb) {
      final index = _webItems.indexWhere((item) => item.id == marker.id);
      if (index < 0) return 0;
      _webItems[index] = marker;
      return 1;
    } else if (_jsonStore case final jsonStore?) {
      count = await jsonStore.access((items) async {
        final index = items.indexWhere((item) => item.id == marker.id);
        if (index < 0) return 0;
        items[index] = marker;
        return 1;
      }, write: true);
    } else {
      final db = await _db;
      final table = await _markerTable(db);
      count = await db.update(table, _values(marker, table),
          where: 'id = ?', whereArgs: [marker.id]);
    }
    if (count > 0) await _cleanRemoved(previous);
    return count;
  }

  Future<int> delete(int id) async {
    if (kIsWeb) {
      final before = _webItems.length;
      _webItems.removeWhere((item) => item.id == id);
      return before == _webItems.length ? 0 : 1;
    }
    final previous = await read(id);
    final int count;
    if (_jsonStore case final jsonStore?) {
      count = await jsonStore.access((items) async {
        final before = items.length;
        items.removeWhere((item) => item.id == id);
        return before - items.length;
      }, write: true);
    } else {
      final db = await _db;
      count = await db
          .delete(await _markerTable(db), where: 'id = ?', whereArgs: [id]);
    }
    if (count > 0) await _cleanRemoved(previous);
    return count;
  }

  Future<void> _cleanRemoved(UserMarker? previous) async {
    if (previous == null || previous.media.isEmpty) return;
    // Never remove attachments still referenced by another marker. Cleanup is
    // best effort, after persistence: an IO error must not roll back saved data.
    try {
      final retained = (await getAll())
          .expand((marker) => marker.media)
          .map((media) => media.fileRef)
          .toSet();
      for (final media in previous.media) {
        if (!retained.contains(media.fileRef)) {
          await _mediaStore.delete(media.fileRef);
        }
      }
    } catch (_) {
      // A locked/missing file can be cleaned later; metadata is already saved.
    }
  }
}
