import 'package:flutter_map/flutter_map.dart';

/// Web использует браузерный HTTP-кэш и штатный сетевой provider.
TileProvider createNetworkTileProvider() => NetworkTileProvider();
