/// Декодер растровых файлов OziExplorer OZF2 / OZF3.
///
/// OZF2 хранит тайлы (обычно 64×64 px) в JPEG-сжатии с таблицей смещений.
/// Декодер читает заголовок, индексирует тайлы и извлекает их по запросу.
library;

import 'dart:io';
import 'dart:typed_data';

/// Один тайл внутри OZF2-файла.
class OzfTile {
  final int x;
  final int y;
  final int offset;
  final int size;

  const OzfTile({
    required this.x,
    required this.y,
    required this.offset,
    required this.size,
  });

  @override
  String toString() => 'OzfTile(x: $x, y: $y, offset: $offset, size: $size)';
}

/// Уровень масштабирования в OZF2.
class OzfLevel {
  final int index;
  final int width; // в тайлах
  final int height; // в тайлах
  final int xOrigin;
  final int yOrigin;
  final List<OzfTile> tiles;

  const OzfLevel({
    required this.index,
    required this.width,
    required this.height,
    required this.xOrigin,
    required this.yOrigin,
    required this.tiles,
  });
}

/// Декодер файлов OZF2.
class OzfDecoder {
  final String filePath;
  final int tileWidth;
  final int tileHeight;
  final int numLevels;
  final List<OzfLevel> levels;

  RandomAccessFile? _raf;

  OzfDecoder._({
    required this.filePath,
    required this.tileWidth,
    required this.tileHeight,
    required this.numLevels,
    required this.levels,
  });

  /// Загружает OZF2-файл.
  factory OzfDecoder.open(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('OZF2 file not found: $filePath');
    }

    final bytes = file.readAsBytesSync();
    return _decode(bytes, filePath);
  }

  static OzfDecoder _decode(Uint8List bytes, String filePath) {
    int pos = 0;

    int readUint16() {
      final value = bytes[pos] | (bytes[pos + 1] << 8);
      pos += 2;
      return value;
    }

    int readUint32() {
      final value = bytes[pos] |
          (bytes[pos + 1] << 8) |
          (bytes[pos + 2] << 16) |
          (bytes[pos + 3] << 24);
      pos += 4;
      // Treat as unsigned 32-bit
      return value < 0 ? value + 0x100000000 : value;
    }

    // --- Header "OZI3" (4 байта) ---
    final sig = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    pos += 4;

    if (sig != 'OZI3') {
      throw Exception('Invalid OZF2 file: missing OZI3 signature (got "$sig")');
    }

    // Version
    readUint32();

    // Palette offset
    readUint32();

    // Tile size (обычно 64)
    final tileWidth = readUint16();
    final tileHeight = readUint16();

    // --- Количество уровней ---
    final numLevels = readUint16();
    readUint16(); // padding / reserved

    if (numLevels < 1 || numLevels > 64) {
      throw Exception('Invalid OZF2 file: unexpected level count $numLevels');
    }

    // --- Чтение заголовков уровней и тайлов ---
    final levels = <OzfLevel>[];

    for (int levelIdx = 0; levelIdx < numLevels; levelIdx++) {
      final levelWidth = readUint16();
      final levelHeight = readUint16();
      final tileCount = readUint32();
      final xOrigin = readUint32();
      final yOrigin = readUint32();
      readUint32(); // level index (redundant)

      if (tileCount == 0 || tileCount > 100000000) continue;

      final tiles = <OzfTile>[];
      for (int i = 0; i < tileCount && pos + 16 <= bytes.length; i++) {
        final tx = readUint32();
        final ty = readUint32();
        final offset = readUint32();
        final size = readUint32();

        if (offset + size <= bytes.length) {
          tiles.add(OzfTile(x: tx, y: ty, offset: offset, size: size));
        }
      }

      levels.add(OzfLevel(
        index: levelIdx,
        width: levelWidth,
        height: levelHeight,
        xOrigin: xOrigin,
        yOrigin: yOrigin,
        tiles: tiles,
      ));
    }

    final decoder = OzfDecoder._(
      filePath: filePath,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      numLevels: numLevels,
      levels: levels,
    );

    // Keep bytes for tile extraction
    decoder._bytes = bytes;

    return decoder;
  }

  Uint8List? _bytes;

  /// Извлекает JPEG-данные указанного тайла.
  Uint8List? getTileData(OzfTile tile) {
    final bytes = _bytes;
    if (bytes == null) return null;
    if (tile.offset + tile.size > bytes.length) return null;
    return Uint8List.sublistView(bytes, tile.offset, tile.offset + tile.size);
  }

  /// Извлекает JPEG-данные тайла по координатам внутри уровня.
  Uint8List? getTile(int levelIdx, int tileX, int tileY) {
    if (levelIdx < 0 || levelIdx >= levels.length) return null;

    final level = levels[levelIdx];
    for (final tile in level.tiles) {
      if (tile.x == tileX && tile.y == tileY) {
        return getTileData(tile);
      }
    }
    return null;
  }

  /// Для OZF2 без .map-калибровки возвращаем тайл по индексу (линейный скан).
  /// Полезно, когда у нас есть только OZF2 без привязки.
  Uint8List? getTileByIndex(int levelIdx, int tileIndex) {
    if (levelIdx < 0 || levelIdx >= levels.length) return null;
    final level = levels[levelIdx];
    if (tileIndex < 0 || tileIndex >= level.tiles.length) return null;
    return getTileData(level.tiles[tileIndex]);
  }

  /// Полные размеры изображения уровня (в пикселях).
  ({int width, int height}) levelPixelSize(int levelIdx) {
    if (levelIdx < 0 || levelIdx >= levels.length) {
      return (width: 0, height: 0);
    }
    final level = levels[levelIdx];
    return (width: level.width * tileWidth, height: level.height * tileHeight);
  }

  /// Освобождение ресурсов.
  void dispose() {
    _bytes = null;
    _raf?.closeSync();
    _raf = null;
  }
}
