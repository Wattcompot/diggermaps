import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_calibration.dart';
import 'ozf2_decoder.dart';

/// TileProvider для связки OZI .map + .ozf2.
class Ozf2TileProvider extends TileProvider {
  final OzfDecoder decoder;
  final OziMapCalibration calibration;

  double pixelOffsetX = 0;
  double pixelOffsetY = 0;

  Ozf2TileProvider({required this.decoder, required this.calibration});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final bounds = _tileBounds(coordinates);
    final pxBounds = _geoToPixelBounds(bounds);
    return _OzfTileImageProvider(
      decoder: decoder,
      pixelBounds: pxBounds,
      tileWidth: 256,
      tileHeight: 256,
    );
  }

  @override
  void dispose() {
    decoder.dispose();
    super.dispose();
  }

  ({double north, double south, double east, double west}) _tileBounds(
      TileCoordinates coords) {
    final n = math.pow(2.0, coords.z);
    final lonWest = coords.x / n * 360.0 - 180.0;
    final lonEast = (coords.x + 1) / n * 360.0 - 180.0;

    final latNorth = _tileYToLat(coords.y, coords.z);
    final latSouth = _tileYToLat(coords.y + 1, coords.z);

    return (north: latNorth, south: latSouth, west: lonWest, east: lonEast);
  }

  double _tileYToLat(int y, int z) {
    final n = math.pi - 2.0 * math.pi * y / math.pow(2.0, z);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  _OzfPixelBounds _geoToPixelBounds(
      ({double north, double south, double east, double west}) geo) {
    final cal = calibration;
    if (cal.points.isEmpty) {
      return const _OzfPixelBounds(minX: 0, minY: 0, maxX: 256, maxY: 256);
    }

    // Обратное преобразование: geo → pixel
    // Используем первую точку как референсную и масштаб по всем точкам
    final p0 = cal.points.first;
    final pLast = cal.points.last;

    final latRange = (pLast.lat - p0.lat).abs();
    final lonRange = (pLast.lon - p0.lon).abs();
    final pxRangeX = (pLast.pixelX - p0.pixelX).abs();
    final pxRangeY = (pLast.pixelY - p0.pixelY).abs();

    final scaleX = pxRangeX / (lonRange < 0.0000001 ? 0.0000001 : lonRange);
    final scaleY = pxRangeY / (latRange < 0.0000001 ? 0.0000001 : latRange);

    int geoToPxX(double lon) =>
        (p0.pixelX + (lon - p0.lon) * scaleX + pixelOffsetX).round();
    int geoToPxY(double lat) =>
        (p0.pixelY + (p0.lat - lat) * scaleY + pixelOffsetY).round();

    return _OzfPixelBounds(
      minX: geoToPxX(geo.west).clamp(0, cal.imageWidth),
      minY: geoToPxY(geo.north).clamp(0, cal.imageHeight),
      maxX: geoToPxX(geo.east).clamp(0, cal.imageWidth),
      maxY: geoToPxY(geo.south).clamp(0, cal.imageHeight),
    );
  }
}

class _OzfPixelBounds {
  final int minX, minY, maxX, maxY;
  const _OzfPixelBounds(
      {required this.minX,
      required this.minY,
      required this.maxX,
      required this.maxY});
  int get width => maxX - minX;
  int get height => maxY - minY;
  bool get isEmpty => width <= 0 || height <= 0;
}

/// Асинхронный ImageProvider для тайлов OZF2.
class _OzfTileImageProvider extends ImageProvider<_OzfTileImageProvider> {
  final OzfDecoder decoder;
  final _OzfPixelBounds pixelBounds;
  final int tileWidth;
  final int tileHeight;

  const _OzfTileImageProvider({
    required this.decoder,
    required this.pixelBounds,
    required this.tileWidth,
    required this.tileHeight,
  });

  @override
  Future<_OzfTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_OzfTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      _OzfTileImageProvider key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    _OzfTileImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final data = _assembleTile();

      if (data == null) {
        throw Exception('No OZF2 tile data');
      }

      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final codec = await decode(buffer);
      return codec;
    } catch (e) {
      chunkEvents.addError(e);
      rethrow;
    } finally {
      chunkEvents.close();
    }
  }

  Uint8List? _assembleTile() {
    if (pixelBounds.isEmpty || decoder.levels.isEmpty) return null;

    final level = decoder.levels.last;
    final ozfTileW = decoder.tileWidth;
    final ozfTileH = decoder.tileHeight;

    final firstTX = pixelBounds.minX ~/ ozfTileW;
    final lastTX = (pixelBounds.maxX - 1) ~/ ozfTileW;
    final firstTY = pixelBounds.minY ~/ ozfTileH;
    final lastTY = (pixelBounds.maxY - 1) ~/ ozfTileH;

    if (lastTX - firstTX > 16 || lastTY - firstTY > 16) {
      return _emptyPng();
    }

    // Собираем JPEG-тайлы
    final parts = <({int x, int y, Uint8List data})>[];
    for (int ty = firstTY; ty <= lastTY; ty++) {
      for (int tx = firstTX; tx <= lastTX; tx++) {
        final data = decoder.getTile(level.index, tx, ty);
        if (data != null) {
          parts.add((x: tx, y: ty, data: data));
        }
      }
    }

    if (parts.isEmpty) return null;
    return parts.first.data;
  }

  Uint8List _emptyPng() {
    return Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x62,
      0x00,
      0x00,
      0x00,
      0x02,
      0x00,
      0x01,
      0xE5,
      0x27,
      0xDE,
      0xFC,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! _OzfTileImageProvider) return false;
    return other.pixelBounds.minX == pixelBounds.minX &&
        other.pixelBounds.minY == pixelBounds.minY &&
        other.pixelBounds.maxX == pixelBounds.maxX &&
        other.pixelBounds.maxY == pixelBounds.maxY;
  }

  @override
  int get hashCode => Object.hash(
        pixelBounds.minX,
        pixelBounds.minY,
        pixelBounds.maxX,
        pixelBounds.maxY,
      );
}
