import '../database/app_database.dart';
import '../models/user_marker.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class UserMarkerRepository {
  final AppDatabase _db = AppDatabase.instance;
  static final List<UserMarker> _webItems = [];
  static int _webId = 0;

  Future<String> _markerTable(Database db) async {
    final markersTable = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: const ['table', 'markers'],
      limit: 1,
    );
    return markersTable.isNotEmpty ? 'markers' : 'user_markers';
  }

  Future<int> create(UserMarker marker) async {
    if (kIsWeb) {
      final id = ++_webId;
      _webItems.add(marker.copyWith(id: id));
      return id;
    }
    final db = await _db.database;
    final table = await _markerTable(db);
    if (table == 'markers') {
      return db.rawInsert(
        'INSERT INTO markers '
        '(name, lat, lng, "desc", icon, color, "group", createdAt, visible) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          marker.name,
          marker.lat,
          marker.lng,
          marker.description,
          marker.shape,
          marker.colorHex,
          marker.group,
          marker.createdAt.toIso8601String(),
          marker.visible ? 1 : 0,
        ],
      );
    }
    final values = Map<String, dynamic>.from(marker.toMap())..remove('id');
    return db.insert(table, values);
  }

  Future<UserMarker?> read(int id) async {
    if (kIsWeb) {
      for (final item in _webItems) {
        if (item.id == id) return item;
      }
      return null;
    }
    final db = await _db.database;
    final table = await _markerTable(db);
    final maps = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return UserMarker.fromMap(maps.first);
    }
    return null;
  }

  Future<List<UserMarker>> getAll() async {
    if (kIsWeb) return List.unmodifiable(_webItems.reversed);
    final db = await _db.database;
    final table = await _markerTable(db);
    final createdAtColumn = table == 'markers' ? 'createdAt' : 'created_at';
    final result = await db.query(table, orderBy: '$createdAtColumn DESC');
    return result.map((json) => UserMarker.fromMap(json)).toList();
  }

  Future<int> update(UserMarker marker) async {
    if (kIsWeb) {
      final index = _webItems.indexWhere((item) => item.id == marker.id);
      if (index < 0) return 0;
      final updatedItems = List<UserMarker>.from(_webItems);
      updatedItems[index] = marker;
      _webItems
        ..clear()
        ..addAll(updatedItems);
      return 1;
    }
    final db = await _db.database;
    final table = await _markerTable(db);
    if (table == 'markers') {
      return db.rawUpdate(
        'UPDATE markers SET name = ?, lat = ?, lng = ?, "desc" = ?, '
        'icon = ?, color = ?, "group" = ?, createdAt = ?, visible = ? '
        'WHERE id = ?',
        [
          marker.name,
          marker.lat,
          marker.lng,
          marker.description,
          marker.shape,
          marker.colorHex,
          marker.group,
          marker.createdAt.toIso8601String(),
          marker.visible ? 1 : 0,
          marker.id,
        ],
      );
    }
    final values = Map<String, dynamic>.from(marker.toMap())..remove('id');
    return db.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [marker.id],
    );
  }

  Future<int> delete(int id) async {
    if (kIsWeb) {
      final before = _webItems.length;
      _webItems.removeWhere((item) => item.id == id);
      return before == _webItems.length ? 0 : 1;
    }
    final db = await _db.database;
    final table = await _markerTable(db);
    return db.delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
