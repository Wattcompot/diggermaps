import '../database/app_database.dart';
import '../models/drawing.dart';
import 'package:flutter/foundation.dart';

class DrawingRepository {
  final AppDatabase _db = AppDatabase.instance;
  static final List<Drawing> _webItems = [];
  static int _webId = 0;

  Future<int> create(Drawing drawing) async {
    if (kIsWeb) {
      final id = ++_webId;
      _webItems.add(drawing.copyWith(id: id));
      return id;
    }
    final db = await _db.database;
    return await db.insert('drawings', drawing.toMap());
  }

  Future<Drawing?> read(int id) async {
    if (kIsWeb) {
      for (final item in _webItems) {
        if (item.id == id) return item;
      }
      return null;
    }
    final db = await _db.database;
    final maps = await db.query(
      'drawings',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Drawing.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Drawing>> getAll() async {
    if (kIsWeb) return List.unmodifiable(_webItems.reversed);
    final db = await _db.database;
    final result = await db.query('drawings', orderBy: 'created_at DESC');
    return result.map((json) => Drawing.fromMap(json)).toList();
  }

  Future<int> update(Drawing drawing) async {
    if (kIsWeb) {
      final index = _webItems.indexWhere((item) => item.id == drawing.id);
      if (index < 0) return 0;
      final updatedItems = List<Drawing>.from(_webItems);
      updatedItems[index] = drawing;
      _webItems
        ..clear()
        ..addAll(updatedItems);
      return 1;
    }
    final db = await _db.database;
    return await db.update(
      'drawings',
      drawing.toMap(),
      where: 'id = ?',
      whereArgs: [drawing.id],
    );
  }

  Future<int> delete(int id) async {
    if (kIsWeb) {
      final before = _webItems.length;
      _webItems.removeWhere((item) => item.id == id);
      return before == _webItems.length ? 0 : 1;
    }
    final db = await _db.database;
    return await db.delete(
      'drawings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
