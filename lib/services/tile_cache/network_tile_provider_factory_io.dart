import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'cached_network_tile_provider.dart';
import 'tile_cache_store.dart';

final TileCacheStore _tileCache = TileCacheStore();
final http.Client _tileHttpClient = http.Client();

TileProvider createNetworkTileProvider() => CachedNetworkTileProvider(
      cache: _tileCache,
      httpClient: _tileHttpClient,
    );
