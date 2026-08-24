library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const double _jnxCoordinateScale = 180.0 / 0x7FFFFFFF;

class JnxTile {
  const JnxTile({
    required this.north,
    required this.east,
    required this.south,
    required this.west,
    required this.width,
    required this.height,
    required this.size,
    required this.offset,
  });

  final double north;
  final double east;
  final double south;
  final double west;
  final int width;
  final int height;
  final int size;
  final int offset;

  bool intersects({
    required double north,
    required double east,
    required double south,
    required double west,
  }) =>
      this.west < east &&
      this.east > west &&
      this.south < north &&
      this.north > south;

  double overlapArea({
    required double north,
    required double east,
    required double south,
    required double west,
  }) {
    final overlapWidth =
        math.max(0.0, math.min(this.east, east) - math.max(this.west, west));
    final overlapHeight = math.max(
        0.0, math.min(this.north, north) - math.max(this.south, south));
    return overlapWidth * overlapHeight;
  }
}

class JnxLevel {
  const JnxLevel({
    required this.index,
    required this.scale,
    required this.tiles,
  });

  final int index;
  final int scale;
  final List<JnxTile> tiles;
}

class JnxMetadata {
  const JnxMetadata({
    required this.version,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.levels,
  });

  final int version;
  final double north;
  final double south;
  final double east;
  final double west;
  final int levels;
}

/// Reader for the little-endian Garmin BirdsEye JNX container.
class JnxDecoder {
  JnxDecoder._({
    required this.filePath,
    required this.metadata,
    required this.levels,
  });

  final String filePath;
  final JnxMetadata metadata;
  final List<JnxLevel> levels;

  factory JnxDecoder.empty(String filePath) => JnxDecoder._(
        filePath: filePath,
        metadata: const JnxMetadata(
          version: 3,
          north: 85,
          south: -85,
          east: 180,
          west: -180,
          levels: 0,
        ),
        levels: const [],
      );

  int get maxZoom => levels.isEmpty ? 18 : _closestWebZoom(levels.last.scale);

  static Future<JnxDecoder> open(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('JNX file not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    return fromBytes(bytes, filePath: filePath);
  }

  static JnxDecoder fromBytes(Uint8List bytes, {String filePath = '<memory>'}) {
    final reader = _LittleEndianReader(bytes);
    if (bytes.length < 48) {
      throw const FormatException('JNX header is truncated');
    }

    final version = reader.uint32();
    reader.uint32(); // device id
    final lat1 = reader.int32() * _jnxCoordinateScale;
    final lon2 = reader.int32() * _jnxCoordinateScale;
    final lat2 = reader.int32() * _jnxCoordinateScale;
    final lon1 = reader.int32() * _jnxCoordinateScale;
    final levelCount = reader.uint32();
    reader.uint32(); // expire
    reader.int32(); // product id
    reader.uint32(); // crc
    reader.uint32(); // signature
    reader.uint32(); // signature offset
    if (version > 3) reader.int32(); // z-order

    if (version < 2 || version > 5) {
      throw FormatException('Unsupported JNX version: $version');
    }
    if (levelCount < 1 || levelCount > 32) {
      throw FormatException('Invalid JNX level count: $levelCount');
    }

    final headers = <({int count, int offset, int scale})>[];
    for (var index = 0; index < levelCount; index++) {
      final count = reader.uint32();
      final offset = reader.uint32();
      final scale = reader.uint32();
      if (version > 3) {
        reader.uint32();
        reader.cString();
      }
      if (count > 10000000 || offset >= bytes.length) {
        throw FormatException('Invalid JNX level table at index $index');
      }
      headers.add((count: count, offset: offset, scale: scale));
    }

    final levels = <JnxLevel>[];
    for (var levelIndex = 0; levelIndex < headers.length; levelIndex++) {
      final header = headers[levelIndex];
      reader.position = header.offset;
      final tiles = <JnxTile>[];
      for (var tileIndex = 0; tileIndex < header.count; tileIndex++) {
        if (reader.remaining < 28) {
          throw FormatException(
              'JNX tile table is truncated at level $levelIndex');
        }
        final top = reader.int32() * _jnxCoordinateScale;
        final right = reader.int32() * _jnxCoordinateScale;
        final bottom = reader.int32() * _jnxCoordinateScale;
        final left = reader.int32() * _jnxCoordinateScale;
        final width = reader.uint16();
        final height = reader.uint16();
        final size = reader.uint32();
        final offset = reader.uint32();
        if (width == 0 ||
            height == 0 ||
            size == 0 ||
            offset + size > bytes.length) {
          continue;
        }
        tiles.add(JnxTile(
          north: math.max(top, bottom),
          east: math.max(left, right),
          south: math.min(top, bottom),
          west: math.min(left, right),
          width: width,
          height: height,
          size: size,
          offset: offset,
        ));
      }
      levels
          .add(JnxLevel(index: levelIndex, scale: header.scale, tiles: tiles));
    }

    if (levels.every((level) => level.tiles.isEmpty)) {
      throw const FormatException('JNX contains no readable tiles');
    }

    return JnxDecoder._(
      filePath: filePath,
      metadata: JnxMetadata(
        version: version,
        north: math.max(lat1, lat2),
        south: math.min(lat1, lat2),
        east: math.max(lon1, lon2),
        west: math.min(lon1, lon2),
        levels: levelCount,
      ),
      levels: levels,
    );
  }

  JnxLevel? levelForWebZoom(int zoom) {
    final nonEmpty = levels.where((level) => level.tiles.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return null;
    final targetMetersPerPixel = 156543.03392804097 / math.pow(2, zoom);
    return nonEmpty.reduce((best, candidate) {
      final bestMeters = best.scale / 130.2084;
      final candidateMeters = candidate.scale / 130.2084;
      final bestError = (math.log(bestMeters / targetMetersPerPixel)).abs();
      final candidateError =
          (math.log(candidateMeters / targetMetersPerPixel)).abs();
      return candidateError < bestError ? candidate : best;
    });
  }

  List<JnxTile> tilesForBounds({
    required int zoom,
    required double north,
    required double east,
    required double south,
    required double west,
  }) {
    final level = levelForWebZoom(zoom);
    if (level == null) return const [];
    final result = level.tiles
        .where((tile) =>
            tile.intersects(north: north, east: east, south: south, west: west))
        .toList();
    result.sort((a, b) => b
        .overlapArea(north: north, east: east, south: south, west: west)
        .compareTo(
            a.overlapArea(north: north, east: east, south: south, west: west)));
    return result;
  }

  Future<Uint8List?> readTile(JnxTile tile) async {
    final file = await File(filePath).open();
    try {
      await file.setPosition(tile.offset);
      final raw = await file.read(tile.size);
      if (raw.length != tile.size) return null;
      if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xD8) return raw;
      return Uint8List.fromList(<int>[0xFF, 0xD8, ...raw]);
    } finally {
      await file.close();
    }
  }

  Future<void> dispose() async {}

  static int _closestWebZoom(int scale) {
    if (scale <= 0) return 18;
    final metersPerPixel = scale / 130.2084;
    return (math.log(156543.03392804097 / metersPerPixel) / math.ln2)
        .round()
        .clamp(0, 24);
  }
}

class _LittleEndianReader {
  _LittleEndianReader(Uint8List bytes)
      : _data = ByteData.sublistView(bytes),
        _length = bytes.length;

  final ByteData _data;
  final int _length;
  int position = 0;

  int get remaining => _length - position;

  void _require(int count) {
    if (position < 0 || position + count > _length) {
      throw const FormatException('Unexpected end of JNX file');
    }
  }

  int uint16() {
    _require(2);
    final value = _data.getUint16(position, Endian.little);
    position += 2;
    return value;
  }

  int uint32() {
    _require(4);
    final value = _data.getUint32(position, Endian.little);
    position += 4;
    return value;
  }

  int int32() {
    _require(4);
    final value = _data.getInt32(position, Endian.little);
    position += 4;
    return value;
  }

  String cString() {
    final units = <int>[];
    while (true) {
      _require(1);
      final value = _data.getUint8(position++);
      if (value == 0) break;
      units.add(value);
      if (units.length > 65536) {
        throw const FormatException('Invalid JNX string');
      }
    }
    return String.fromCharCodes(units);
  }
}
