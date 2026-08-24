import '../database/app_database.dart';
import '../models/track.dart';
import 'package:flutter/foundation.dart';

class TrackRepository {
  final AppDatabase _db = AppDatabase.instance;
  static final List<Track> _webItems = [];
  static int _webId = 0;

  Future<int> create(Track track) async {
    if (kIsWeb) {
      final id = ++_webId;
      _webItems.add(track.copyWith(id: id));
      return id;
    }
    final db = await _db.database;
    return await db.insert('tracks', track.toMap());
  }

  Future<Track?> read(int id) async {
    if (kIsWeb) {
      for (final item in _webItems) {
        if (item.id == id) return item;
      }
      return null;
    }
    final db = await _db.database;
    final maps = await db.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Track.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Track>> getAll() async {
    if (kIsWeb) return List.unmodifiable(_webItems.reversed);
    final db = await _db.database;
    final result = await db.query('tracks', orderBy: 'created_at DESC');
    return result.map((json) => Track.fromMap(json)).toList();
  }

  Future<int> update(Track track) async {
    if (kIsWeb) {
      final index = _webItems.indexWhere((item) => item.id == track.id);
      if (index < 0) return 0;
      _webItems[index] = track;
      return 1;
    }
    final db = await _db.database;
    return await db.update(
      'tracks',
      track.toMap(),
      where: 'id = ?',
      whereArgs: [track.id],
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
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
