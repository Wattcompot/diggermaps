import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'jnx_decoder.dart';

class JnxTileProvider extends TileProvider {
  JnxTileProvider({required this.decoder});

  final JnxDecoder decoder;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _JnxImageProvider(
          decoder: decoder,
          z: coordinates.z,
          x: coordinates.x,
          y: coordinates.y);
}

class _JnxImageProvider extends ImageProvider<_JnxImageProvider> {
  const _JnxImageProvider(
      {required this.decoder,
      required this.z,
      required this.x,
      required this.y});

  final JnxDecoder decoder;
  final int z;
  final int x;
  final int y;

  @override
  Future<_JnxImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      _JnxImageProvider key, ImageDecoderCallback decode) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(decode, chunks),
      chunkEvents: chunks.stream,
      scale: 1,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode,
      StreamController<ImageChunkEvent> chunks) async {
    try {
      final bounds = _tileBounds(x, y, z);
      final candidates = decoder.tilesForBounds(
        zoom: z,
        north: bounds.north,
        east: bounds.east,
        south: bounds.south,
        west: bounds.west,
      );
      if (candidates.isEmpty) {
        throw StateError('No JNX coverage at z=$z x=$x y=$y');
      }
      final bytes = await decoder.readTile(candidates.first);
      if (bytes == null) {
        throw StateError('Cannot read JNX tile bytes');
      }
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (error) {
      chunks.addError(error);
      rethrow;
    } finally {
      await chunks.close();
    }
  }

  static ({double north, double east, double south, double west}) _tileBounds(
      int x, int y, int z) {
    final count = math.pow(2.0, z);
    return (
      north: _tileYToLat(y, z),
      east: (x + 1) / count * 360 - 180,
      south: _tileYToLat(y + 1, z),
      west: x / count * 360 - 180,
    );
  }

  static double _tileYToLat(int y, int z) {
    final n = math.pi - 2 * math.pi * y / math.pow(2.0, z);
    return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  @override
  bool operator ==(Object other) =>
      other is _JnxImageProvider &&
      other.decoder.filePath == decoder.filePath &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(decoder.filePath, z, x, y);
}
