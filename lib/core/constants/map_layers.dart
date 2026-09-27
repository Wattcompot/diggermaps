/// URL-шаблоны и параметры слоёв карты.
class MapLayers {
  const MapLayers._();

  static const userAgentPackageName = 'com.diggermaps.app';
  static const tileSubdomains = <String>['a', 'b', 'c'];

  /// Единый предел приближения для всех слоёв карты.
  ///
  /// Источники тайлов имеют разный «родной» максимум (OSM 19, ESRI 18,
  /// OpenTopo 17 и т.д.). Раньше `MapOptions.maxZoom` и `TileLayer.maxZoom`
  /// брались из этого родного максимума, поэтому:
  ///  * приближение было неодинаковым и зависело от выбранного слоя;
  ///  * стоило подняться выше родного зума (или переключиться на слой с
  ///    меньшим максимумом), как `TileLayer` переставал рисовать тайлы и карта
  ///    становилась чёрной (фон `0xFF1A1A1A`).
  ///
  /// Теперь предел камеры единый и равен [maxUserZoom], а каждый [TileLayer]
  /// получает `maxNativeZoom` = родной максимум источника и `maxZoom` =
  /// [maxUserZoom]. Выше родного зума flutter_map масштабирует последние
  /// загруженные тайлы (over-zoom), поэтому картинка становится крупнее, но не
  /// пропадает.
  static const double maxUserZoom = 22;

  static const esriWorldImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const esriReference =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
  static const openStreetMap = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const openTopoMap = 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
  static const cartoDarkMatter =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  static const historicalDemoTiles = openTopoMap;
  static const wikimapiaBaseUrl = 'https://api.wikimapia.org/';
  static const planetaryComputerBaseUrl =
      'https://planetarycomputer.microsoft.com/api/data/v1';
  static const nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
}
