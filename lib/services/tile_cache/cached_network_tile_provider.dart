import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'tile_cache_store.dart';

/// Сетевой TileProvider с дисковым кэшем на IO-платформах.
///
/// Для Web следует использовать штатный [NetworkTileProvider], поскольку
/// браузер не предоставляет `dart:io` и сам управляет HTTP-кэшем.
class CachedNetworkTileProvider extends TileProvider {
  CachedNetworkTileProvider({
    required this.cache,
    required http.Client httpClient,
    super.headers,
  }) : _client = httpClient;

  final TileCacheStore cache;
  final http.Client _client;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedTileImageProvider(
      url: getTileUrl(coordinates, options),
      headers: Map<String, String>.unmodifiable(headers),
      cache: cache,
      client: _client,
    );
  }

  @override
  void dispose() {
    // Клиент общий для всех сетевых слоёв и живёт до завершения процесса.
    // flutter_map вызывает dispose() у TileProvider при удалении каждого слоя.
    super.dispose();
  }
}

@immutable
class CachedTileImageProvider extends ImageProvider<CachedTileImageProvider> {
  const CachedTileImageProvider({
    required this.url,
    required this.headers,
    required this.cache,
    required this.client,
  });

  final String url;
  final Map<String, String> headers;
  final TileCacheStore cache;
  final http.Client client;

  @override
  Future<CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadBytes(key, decode),
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('URL', url),
        DiagnosticsProperty<CachedTileImageProvider>('Provider', key),
      ],
    );
  }

  Future<ui.Codec> _loadBytes(
    CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final cached = await cache.read(url);
    if (cached != null) {
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(cached));
      } catch (_) {
        // Повреждённый/устаревший файл заменится свежим ответом сети.
      }
    }

    final response = await client.get(Uri.parse(url), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      throw http.ClientException(
        'Tile request failed with HTTP ${response.statusCode}',
        Uri.parse(url),
      );
    }

    final bytes = response.bodyBytes;
    unawaited(cache.write(url, bytes));
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedTileImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
