import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

class OzfTileProvider extends TileProvider {
  OzfTileProvider({
    required this.ozfPath,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final String ozfPath;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _OzfTileImageProvider(
      ozfPath: ozfPath,
      zoom: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }
}

class _OzfTileImageProvider extends ImageProvider<_OzfTileImageProvider> {
  const _OzfTileImageProvider({
    required this.ozfPath,
    required this.zoom,
    required this.x,
    required this.y,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  static const MethodChannel _channel =
      MethodChannel('com.diggermaps/ozf_decoder');
  static const int _maxCacheEntries = 256;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, Future<Uint8List>> _pending = {};
  static final Uint8List _transparentTile = Uint8List.fromList(const [
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

  final String ozfPath;
  final int zoom;
  final int x;
  final int y;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  String get _cacheKey =>
      '$ozfPath|$zoom|$x|$y|$minLatitude|$maxLatitude|$minLongitude|$maxLongitude';

  @override
  Future<_OzfTileImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _OzfTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(decode, chunks),
      chunkEvents: chunks.stream,
      scale: 1,
    );
  }

  Future<ui.Codec> _load(
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      final bytes = await _loadBytes();
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (error) {
      chunks.addError(error);
      rethrow;
    } finally {
      await chunks.close();
    }
  }

  Future<Uint8List> _loadBytes() async {
    final cached = _cache.remove(_cacheKey);
    if (cached != null) {
      _cache[_cacheKey] = cached;
      return cached;
    }
    return _pending.putIfAbsent(_cacheKey, () async {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('getTile', {
          'ozfPath': ozfPath,
          'zoom': zoom,
          'x': x,
          'y': y,
          'minLatitude': minLatitude,
          'maxLatitude': maxLatitude,
          'minLongitude': minLongitude,
          'maxLongitude': maxLongitude,
        });
        final result = bytes ?? _transparentTile;
        _cache[_cacheKey] = result;
        while (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        return result;
      } finally {
        _pending.remove(_cacheKey);
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is _OzfTileImageProvider && other._cacheKey == _cacheKey;

  @override
  int get hashCode => _cacheKey.hashCode;
}
