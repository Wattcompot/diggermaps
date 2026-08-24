import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

class LocalRasterTileProvider extends TileProvider {
  LocalRasterTileProvider({
    required this.imagePath,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final String imagePath;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _LocalRasterImageProvider(
        imagePath: imagePath,
        zoom: coordinates.z,
        x: coordinates.x,
        y: coordinates.y,
        minLatitude: minLatitude,
        maxLatitude: maxLatitude,
        minLongitude: minLongitude,
        maxLongitude: maxLongitude,
      );
}

class _LocalRasterImageProvider
    extends ImageProvider<_LocalRasterImageProvider> {
  const _LocalRasterImageProvider({
    required this.imagePath,
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
  static const int _maxCacheEntries = 96;
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, Future<Uint8List>> _pending = {};

  final String imagePath;
  final int zoom;
  final int x;
  final int y;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  String get _cacheKey =>
      '$imagePath|$zoom|$x|$y|$minLatitude|$maxLatitude|$minLongitude|$maxLongitude';

  @override
  Future<_LocalRasterImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _LocalRasterImageProvider key,
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
        final bytes = await _channel.invokeMethod<Uint8List>('getRasterTile', {
          'imagePath': imagePath,
          'zoom': zoom,
          'x': x,
          'y': y,
          'minLatitude': minLatitude,
          'maxLatitude': maxLatitude,
          'minLongitude': minLongitude,
          'maxLongitude': maxLongitude,
        });
        if (bytes == null) throw StateError('Тайл вне границ растра');
        _cache[_cacheKey] = bytes;
        while (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        return bytes;
      } finally {
        _pending.remove(_cacheKey);
      }
    });
  }

  @override
  bool operator ==(Object other) =>
      other is _LocalRasterImageProvider && other._cacheKey == _cacheKey;

  @override
  int get hashCode => _cacheKey.hashCode;
}
