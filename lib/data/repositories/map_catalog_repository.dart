import 'package:path/path.dart' as p;
import 'custom_map_repository.dart';

class MapCatalogRepository {
  /// Возвращает список предустановленных источников карт.
  List<CustomMapLayer> getDefaultSources() {
    return [
      const CustomMapLayer(
        id: 'osm',
        name: 'OpenStreetMap',
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        maxZoom: 19,
        type: MapLayerType.base,
        sourceType: MapSourceType.network,
      ),
      const CustomMapLayer(
        id: 'esri_world_imagery',
        name: 'Esri World Imagery',
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 18,
        type: MapLayerType.base,
        sourceType: MapSourceType.network,
      ),
      const CustomMapLayer(
        id: 'esri_reference',
        name: 'Esri Reference',
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 18,
        type: MapLayerType.overlay,
        sourceType: MapSourceType.network,
      ),
      const CustomMapLayer(
        id: 'opentopomap',
        name: 'OpenTopoMap',
        urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
        maxZoom: 17,
        type: MapLayerType.base,
        sourceType: MapSourceType.network,
      ),
    ];
  }

  /// Импортирует метаданные файла и возвращает объект слоя.
  /// Поддерживаемые расширения: .mbtiles, .sqlitedb, .map, .ozf2, .jnx.
  CustomMapLayer? importFileMetadata(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    final fileName = p.basenameWithoutExtension(filePath);

    // Whitelist проверок
    final whitelist = {
      '.mbtiles',
      '.sqlitedb',
      '.map',
      '.ozf2',
      '.ozf',
      '.ozfx3',
      '.jnx',
      '.kml',
      '.kmz',
      '.gpx',
      '.tif',
      '.tiff',
      '.img',
      '.birdseye',
    };
    if (!whitelist.contains(extension)) {
      return null;
    }

    MapSourceType sourceType;
    bool isRenderable = false;
    String? validationMessage;

    switch (extension) {
      case '.mbtiles':
        sourceType = MapSourceType.mbtiles;
        isRenderable = true; // MBTiles renderable directly
        break;
      case '.sqlitedb':
        // Many field-map `.sqlitedb` files use the MBTiles schema. They are
        // opened through the same provider; incompatible schemas are reported
        // by the tile provider instead of silently being treated as network URLs.
        sourceType = MapSourceType.mbtiles;
        isRenderable = true;
        validationMessage =
            'Открывается как совместимая с MBTiles SQLitedb-карта';
        break;
      case '.map':
        sourceType = MapSourceType.oziMap;
        isRenderable = true;
        validationMessage =
            'Калибровка OziExplorer: ищет связанный .ozf2 в той же папке.';
        break;
      case '.ozf2':
      case '.ozf':
      case '.ozfx3':
        sourceType = MapSourceType.ozf2;
        isRenderable = true;
        validationMessage =
            'Растр OZF2: ищет файл калибровки .map в той же папке.';
        break;
      case '.jnx':
        sourceType = MapSourceType.jnx;
        isRenderable = true;
        validationMessage = 'Карта Garmin JNX: тайлы читаются из SQLite-базы.';
        break;
      case '.birdseye':
        sourceType = MapSourceType.birdseye;
        isRenderable = true;
        validationMessage = 'BirdsEye: ожидается JNX-совместимый файл.';
        break;
      case '.kml':
        sourceType = MapSourceType.kml;
        validationMessage = 'KML импортирован как геоданные.';
        break;
      case '.kmz':
        sourceType = MapSourceType.kmz;
        validationMessage = 'KMZ импортирован как архив KML.';
        break;
      case '.gpx':
        sourceType = MapSourceType.gpx;
        validationMessage = 'GPX импортирован как трек/маршрут.';
        break;
      case '.tif':
      case '.tiff':
        sourceType = MapSourceType.geotiff;
        validationMessage =
            'GeoTIFF сохранён; требуется GeoTIFF tile provider для показа.';
        break;
      case '.img':
        sourceType = MapSourceType.garminImg;
        validationMessage =
            'Garmin IMG сохранён; требуется векторный Garmin decoder.';
        break;
      default:
        return null;
    }

    return CustomMapLayer(
      id: 'file_${DateTime.now().millisecondsSinceEpoch}',
      name: fileName,
      urlTemplate: filePath,
      maxZoom: 18,
      type: MapLayerType.overlay, // Default to overlay for imported files
      sourceType: sourceType,
      filePath: filePath,
      isRenderable: isRenderable,
      enabled: true,
      validationMessage: validationMessage,
    );
  }
}
