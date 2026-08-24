import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is disabled on Web');
    }
    if (_database != null) return _database!;
    _database = await _initDB('digger_maps.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 12,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullableType = 'TEXT';
    const doubleType = 'REAL NOT NULL';
    const integerType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE user_markers (
        id $idType,
        name $textType,
        description $textNullableType,
        lat $doubleType,
        lng $doubleType,
        color_hex $textType,
        marker_shape TEXT NOT NULL DEFAULT 'pin',
        marker_size REAL NOT NULL DEFAULT 42,
        marker_group TEXT NOT NULL DEFAULT 'Общее',
        visible INTEGER NOT NULL DEFAULT 1,
        created_at $textType
      )
    ''');

    await db.execute('''
      CREATE TABLE drawings (
        id $idType,
        name $textType,
        description $textNullableType,
        type $textType,
        category TEXT NOT NULL DEFAULT 'drawing',
        points_json $textType,
        geojson TEXT,
        color $integerType,
        stroke_width $doubleType,
        fill_opacity $doubleType,
        visible INTEGER NOT NULL DEFAULT 1,
        created_at $textType
      )
    ''');

    await db.execute('''
      CREATE TABLE tracks (
        id $idType,
        name $textType,
        description $textNullableType,
        points_json $textType,
        distance $doubleType,
        duration $integerType,
        color INTEGER NOT NULL DEFAULT 4294901760,
        visible INTEGER NOT NULL DEFAULT 0,
        segments_json TEXT NOT NULL DEFAULT '[]',
        created_at $textType
      )
    ''');

    await db.execute('''
      CREATE TABLE imported_maps (
        id $idType,
        name $textType,
        path TEXT,
        type TEXT,
        bounds TEXT,
        min_zoom INTEGER,
        max_zoom INTEGER,
        visible INTEGER NOT NULL DEFAULT 1,
        created_at $textType,
        map_file_path TEXT,
        image_file_path TEXT,
        format TEXT,
        bounds_json TEXT,
        calibration_points_json TEXT,
        offset_x REAL NOT NULL DEFAULT 0,
        offset_y REAL NOT NULL DEFAULT 0,
        opacity REAL NOT NULL DEFAULT 0.7
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Миграция с версии 1 на 2
      // 1. Обновление user_markers
      final userMarkersTable =
          await db.rawQuery('PRAGMA table_info(user_markers)');
      final userColumns =
          userMarkersTable.map((c) => c['name'] as String).toSet();

      if (!userColumns.contains('name')) {
        await db.execute('ALTER TABLE user_markers ADD COLUMN name TEXT');
        await db
            .execute('UPDATE user_markers SET name = title WHERE name IS NULL');
      }
      if (!userColumns.contains('lat')) {
        await db.execute('ALTER TABLE user_markers ADD COLUMN lat REAL');
        await db.execute(
            'UPDATE user_markers SET lat = latitude WHERE lat IS NULL');
      }
      if (!userColumns.contains('lng')) {
        await db.execute('ALTER TABLE user_markers ADD COLUMN lng REAL');
        await db.execute(
            'UPDATE user_markers SET lng = longitude WHERE lng IS NULL');
      }
      if (!userColumns.contains('color_hex')) {
        await db.execute('ALTER TABLE user_markers ADD COLUMN color_hex TEXT');
        await db.execute(
            'UPDATE user_markers SET color_hex = color WHERE color_hex IS NULL');
      }

      // 2. Обновление drawings
      final drawingsTable = await db.rawQuery('PRAGMA table_info(drawings)');
      final drawingColumns =
          drawingsTable.map((c) => c['name'] as String).toSet();

      if (!drawingColumns.contains('type')) {
        await db.execute(
            "ALTER TABLE drawings ADD COLUMN type TEXT DEFAULT 'line'");
      }
      if (!drawingColumns.contains('fill_opacity')) {
        await db.execute(
            'ALTER TABLE drawings ADD COLUMN fill_opacity REAL DEFAULT 0.5');
      }

      // Обработка смены типа color с String на Integer в sqlite сложна,
      // но sqlite позволяет менять типы данных динамически.
      // Однако для безопасности данных при обновлении оставим как есть,
      // либо попробуем конвертировать если это цвет в формате #RRGGBB.
    }
    if (oldVersion < 3) {
      final markerColumns =
          (await db.rawQuery('PRAGMA table_info(user_markers)'))
              .map((column) => column['name'] as String)
              .toSet();
      if (!markerColumns.contains('marker_shape')) {
        await db.execute(
            "ALTER TABLE user_markers ADD COLUMN marker_shape TEXT NOT NULL DEFAULT 'pin'");
      }
      if (!markerColumns.contains('marker_size')) {
        await db.execute(
            'ALTER TABLE user_markers ADD COLUMN marker_size REAL NOT NULL DEFAULT 42');
      }
      if (!markerColumns.contains('marker_group')) {
        await db.execute(
            "ALTER TABLE user_markers ADD COLUMN marker_group TEXT NOT NULL DEFAULT 'Общее'");
      }
    }
    if (oldVersion < 4) {
      final drawingColumns = (await db.rawQuery('PRAGMA table_info(drawings)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!drawingColumns.contains('visible')) {
        await db.execute(
            'ALTER TABLE drawings ADD COLUMN visible INTEGER NOT NULL DEFAULT 1');
      }
      final trackColumns = (await db.rawQuery('PRAGMA table_info(tracks)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!trackColumns.contains('visible')) {
        await db.execute(
            'ALTER TABLE tracks ADD COLUMN visible INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 5) {
      final columns = (await db.rawQuery('PRAGMA table_info(drawings)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!columns.contains('category')) {
        await db.execute(
            "ALTER TABLE drawings ADD COLUMN category TEXT NOT NULL DEFAULT 'drawing'");
      }
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS imported_maps (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          path TEXT NOT NULL,
          type TEXT NOT NULL,
          bounds TEXT,
          min_zoom INTEGER,
          max_zoom INTEGER,
          visible INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      final drawingColumns = (await db.rawQuery('PRAGMA table_info(drawings)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!drawingColumns.contains('geojson')) {
        await db.execute('ALTER TABLE drawings ADD COLUMN geojson TEXT');
      }
    }
    if (oldVersion < 8) {
      for (final table in const ['user_markers', 'markers']) {
        final exists = await db.rawQuery(
          'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
          ['table', table],
        );
        if (exists.isEmpty) continue;
        final columns = (await db.rawQuery('PRAGMA table_info($table)'))
            .map((column) => column['name'] as String)
            .toSet();
        if (!columns.contains('visible')) {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN visible INTEGER NOT NULL DEFAULT 1',
          );
        }
      }
    }
    if (oldVersion < 9) {
      // -- migration to v9: расширяем imported_maps новыми колонками ----------
      final exists = await db.rawQuery(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
        ['table', 'imported_maps'],
      );
      if (exists.isNotEmpty) {
        final columns = (await db.rawQuery('PRAGMA table_info(imported_maps)'))
            .map((c) => c['name'] as String)
            .toSet();

        // Add missing columns with sensible defaults.
        if (!columns.contains('map_file_path')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN map_file_path TEXT',
          );
        }
        if (!columns.contains('image_file_path')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN image_file_path TEXT',
          );
        }
        if (!columns.contains('format')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN format TEXT',
          );
        }
        if (!columns.contains('bounds_json')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN bounds_json TEXT',
          );
        }
        if (!columns.contains('calibration_points_json')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN calibration_points_json TEXT',
          );
        }
        if (!columns.contains('offset_x')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN offset_x REAL NOT NULL DEFAULT 0',
          );
        }
        if (!columns.contains('offset_y')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN offset_y REAL NOT NULL DEFAULT 0',
          );
        }
        if (!columns.contains('opacity')) {
          await db.execute(
            'ALTER TABLE imported_maps ADD COLUMN opacity REAL NOT NULL DEFAULT 0.7',
          );
        }

        // Backfill: format ← type (only when format is NULL).
        if (columns.contains('type')) {
          await db.execute(
            "UPDATE imported_maps SET format = type WHERE format IS NULL AND type IS NOT NULL",
          );
        } else {
          await db.execute(
            "UPDATE imported_maps SET format = 'raster' WHERE format IS NULL",
          );
        }

        // Backfill: map_file_path ← path when path ends with .map.
        if (columns.contains('path')) {
          await db.execute(
            "UPDATE imported_maps SET map_file_path = path WHERE map_file_path IS NULL AND path IS NOT NULL AND path LIKE '%.map'",
          );
        }

        // Backfill: image_file_path ← path for raster / mbtiles (non-.map).
        if (columns.contains('path') && columns.contains('type')) {
          await db.execute(
            "UPDATE imported_maps SET image_file_path = path WHERE image_file_path IS NULL AND path IS NOT NULL AND (path NOT LIKE '%.map' OR type IN ('mbtiles','ozf2','jnx'))",
          );
        }

        // Backfill: bounds_json ← bounds.
        if (columns.contains('bounds')) {
          await db.execute(
            'UPDATE imported_maps SET bounds_json = bounds WHERE bounds_json IS NULL AND bounds IS NOT NULL',
          );
        }
      }
    }
    if (oldVersion < 10) {
      final trackColumns = (await db.rawQuery('PRAGMA table_info(tracks)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!trackColumns.contains('color')) {
        await db.execute(
          'ALTER TABLE tracks ADD COLUMN color INTEGER NOT NULL DEFAULT 4294901760',
        );
      }
    }
    if (oldVersion < 11) {
      for (final table in const ['drawings', 'tracks']) {
        final columns = (await db.rawQuery('PRAGMA table_info($table)'))
            .map((column) => column['name'] as String)
            .toSet();
        if (!columns.contains('description')) {
          await db.execute('ALTER TABLE $table ADD COLUMN description TEXT');
        }
      }
    }
    if (oldVersion < 12) {
      final trackColumns = (await db.rawQuery('PRAGMA table_info(tracks)'))
          .map((column) => column['name'] as String)
          .toSet();
      if (!trackColumns.contains('segments_json')) {
        await db.execute(
          "ALTER TABLE tracks ADD COLUMN segments_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
