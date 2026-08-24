/// URL-шаблоны и параметры слоёв карты.
class MapLayers {
  const MapLayers._();

  static const userAgentPackageName = 'com.diggermaps.app';
  static const tileSubdomains = <String>['a', 'b', 'c'];

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
