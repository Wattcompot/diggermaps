import 'dart:convert';

import 'package:digger_maps/utils/ozi_map_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// Вспомогательные функции для генерации тестовых .map-контентов
// =============================================================================

String _buildMMPLLContent({
  String raster = 'topo.jpg',
  int width = 2048,
  int height = 1536,
  List<String>? extraPoints,
}) {
  return [
    'OziExplorer Map Data File Version 2.1',
    'Test Map Name',
    raster,
    'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
    'Reserved 1',
    'Reserved 2',
    'IWH,Map Image Width/Height,$width,$height',
    'Point01,xy,100,200,in,deg,55,30.000,N,37,36.000,E, grid, , , ,',
    'Point02,xy,1900,200,in,deg,55,30.500,N,37,37.000,E, grid, , , ,',
    'Point03,xy,100,1400,in,deg,55,29.000,N,37,36.500,E, grid, , , ,',
    if (extraPoints != null) ...extraPoints,
    'MMPNUM,3',
    '',
  ].join('\n');
}

String _buildMMPXYContent({
  String raster = 'map.png',
  int width = 1024,
  int height = 768,
}) {
  return [
    'OziExplorer Map Data File Version 2.1',
    'MMPXY Test Map',
    raster,
    'MMPXY',
    'Projection,UTM Zone 37',
    'Datum,WGS 84',
    'IWH,Map Image Width/Height,$width,$height',
    'MMPNUM,2',
    'MMPXY,1,100,200',
    'MMPLL,1,37.6,55.5',
    'MMPXY,2,900,700',
    'MMPLL,2,37.7,55.6',
    '',
  ].join('\n');
}

// =============================================================================
// Тесты
// =============================================================================

void main() {
  group('OziMapParser.parseString — MMPLL', () {
    test('извлекает rasterPath из третьей строки', () {
      final content = _buildMMPLLContent();
      final result = OziMapParser.parseString(content);
      expect(result.rasterPath, 'topo.jpg');
    });

    test('извлекает imageWidth и imageHeight из IWH', () {
      final content = _buildMMPLLContent(width: 3200, height: 2400);
      final result = OziMapParser.parseString(content);
      expect(result.imageWidth, 3200);
      expect(result.imageHeight, 2400);
    });

    test('распознаёт Point01, Point02, Point03', () {
      final content = _buildMMPLLContent();
      final result = OziMapParser.parseString(content);
      expect(result.points.length, 3);

      // Point01: pixel (100, 200), geo (55.5 N, 37.6 E)
      final p1 = result.points.firstWhere((p) => p.pixelX == 100);
      expect(p1.pixelY, 200);
      expect(p1.lat, closeTo(55.5, 0.0001));
      expect(p1.lng, closeTo(37.6, 0.0001));

      // Point02: pixel (1900, 200), geo (55.50833 N, 37.61667 E)
      final p2 = result.points.firstWhere((p) => p.pixelX == 1900);
      expect(p2.pixelY, 200);
      expect(p2.lat, closeTo(55 + 30.5 / 60, 0.0001));
      expect(p2.lng, closeTo(37 + 37.0 / 60, 0.0001));

      // Point03: pixel (100, 1400), geo (55.48333 N, 37.60833 E)
      final p3 = result.points.firstWhere((p) => p.pixelY == 1400);
      expect(p3.pixelX, 100);
      expect(p3.lat, closeTo(55 + 29.0 / 60, 0.0001));
      expect(p3.lng, closeTo(37 + 36.5 / 60, 0.0001));
    });

    test('корректно обрабатывает южное полушарие (S) и западную долготу (W)',
        () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Southern Map',
        'south.jpg',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'IWH,Map Image Width/Height,1000,1000',
        'Point01,xy,100,200,in,deg,33,55.500,S,18,25.750,E, grid, , , ,',
        'Point02,xy,900,200,in,deg,33,55.000,S,18,26.500,E, grid, , , ,',
        'Point03,xy,100,800,in,deg,33,54.500,S,18,25.000,W, grid, , , ,',
        'MMPNUM,3',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);

      // Point01: S → negative lat
      final p1 = result.points.firstWhere((p) => p.pixelX == 100);
      expect(p1.lat, lessThan(0)); // ~ -33.925
      expect(p1.lat, closeTo(-(33 + 55.5 / 60), 0.0001));
      expect(p1.lng, greaterThan(0)); // ~ 18.429

      // Point03: W → negative lng
      final p3 =
          result.points.firstWhere((p) => p.pixelX == 100 && p.pixelY == 800);
      expect(p3.lng, lessThan(0)); // ~ -18.416
      expect(p3.lng, closeTo(-(18 + 25.0 / 60), 0.0001));
    });

    test('не принимает UTM Point как градусы широты и долготы', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Projected point',
        'utm.ozf2',
        'IWH,Map Image Width/Height,1000,1000',
        'Point01,xy,100,200,in,utm,37,N,500000,6200000,,,, grid, , , ,',
        'MMPNUM,1',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.points, isEmpty);
      expect(result.boundsJson, isNull);
    });

    test('пропускает невалидные точки (без ошибок)', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Bad Points Map',
        'bad.jpg',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'IWH,Map Image Width/Height,500,500',
        // Плохая точка — не хватает полей
        'Point01,xy,100,200,in',
        // Хорошая точка
        'Point02,xy,200,300,in,deg,55,30.000,N,37,36.000,E, grid, , , ,',
        // Пустая строка с Point
        'Point03',
        'MMPNUM,3',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      // Только валидная Point02 должна быть распарсена.
      expect(result.points.length, 1);
    });

    test('извлекает Projection и Datum', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Projected Map',
        'proj.jpg',
        'MMPLL',
        'Projection,UTM Zone 37',
        'Datum,Pulkovo 1942',
        'IWH,Map Image Width/Height,800,600',
        'Point01,xy,100,200,in,deg,55,30.000,N,37,36.000,E, grid, , , ,',
        'MMPNUM,1',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.projection, 'UTM Zone 37');
      expect(result.datum, 'Pulkovo 1942');
    });
  });

  group('OziMapParser.parseString — MMPXY + MMPLL', () {
    test('извлекает точки через MMPXY и MMPLL', () {
      final content = _buildMMPXYContent();
      final result = OziMapParser.parseString(content);

      expect(result.calibrationType, 'MMPXY');
      expect(result.points.length, 2);

      final p1 = result.points.firstWhere((p) => p.pixelX == 100);
      expect(p1.pixelY, 200);
      expect(p1.lat, closeTo(55.5, 0.0001));
      expect(p1.lng, closeTo(37.6, 0.0001));

      final p2 = result.points.firstWhere((p) => p.pixelX == 900);
      expect(p2.pixelY, 700);
      expect(p2.lat, closeTo(55.6, 0.0001));
      expect(p2.lng, closeTo(37.7, 0.0001));
    });

    test('пропускает MMPXY без соответствующего MMPLL', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Partial MMP Map',
        'partial.png',
        'MMPXY',
        'IWH,Map Image Width/Height,400,300',
        'MMPNUM,2',
        'MMPXY,1,50,60',
        'MMPLL,1,37.5,55.5',
        'MMPXY,2,350,280',
        // MMPLL для 2 отсутствует
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      // Только MMP1 имеет обе записи (XY + LL).
      expect(result.points.length, 1);
      expect(result.points.first.pixelX, 50);
      expect(result.points.first.pixelY, 60);
    });
  });

  group('OziMapParser — Image File явная строка', () {
    test('извлекает rasterPath из "Image File," строки', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Explicit Image Map',
        '',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'Image File,C:\\Maps\\explicit_raster.jpg',
        'IWH,Map Image Width/Height,1024,768',
        'Point01,xy,100,200,in,deg,55,30.000,N,37,36.000,E, grid, , , ,',
        'MMPNUM,1',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.rasterPath, 'C:\\Maps\\explicit_raster.jpg');
    });

    test('Image File с пробелами', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Space Map',
        '',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'Image File,   /maps/my raster.png   ',
        'IWH,Map Image Width/Height,512,512',
        'Point01,xy,0,0,in,deg,50,0.000,N,30,0.000,E, grid, , , ,',
        'MMPNUM,1',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.rasterPath, '/maps/my raster.png');
    });
  });

  group('OziMapParseResult — bounds', () {
    test('boundsJson охватывает все калибровочные точки', () {
      final content = _buildMMPLLContent();
      final result = OziMapParser.parseString(content);

      final bounds = result.boundsJson;
      expect(bounds, isNotNull);

      final map = jsonDecode(bounds!) as Map<String, dynamic>;
      for (final point in result.points) {
        expect((map['minLat'] as num).toDouble(), lessThanOrEqualTo(point.lat));
        expect(
            (map['maxLat'] as num).toDouble(), greaterThanOrEqualTo(point.lat));
        expect((map['minLng'] as num).toDouble(), lessThanOrEqualTo(point.lng));
        expect(
            (map['maxLng'] as num).toDouble(), greaterThanOrEqualTo(point.lng));
      }
    });

    test('boundsJson экстраполирует границы до углов изображения', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Inset calibration points',
        'inset.ozf2',
        'IWH,Map Image Width/Height,1000,1000',
        'MMPNUM,3',
        'MMPXY,1,100,100',
        'MMPLL,1,10.1,49.9',
        'MMPXY,2,900,100',
        'MMPLL,2,10.9,49.9',
        'MMPXY,3,100,900',
        'MMPLL,3,10.1,49.1',
      ].join('\n');

      final bounds = OziMapParser.parseString(content).boundsAsMap!;
      expect(bounds['minLat'], closeTo(49.0, 0.0001));
      expect(bounds['maxLat'], closeTo(50.0, 0.0001));
      expect(bounds['minLng'], closeTo(10.0, 0.0001));
      expect(bounds['maxLng'], closeTo(11.0, 0.0001));
    });

    test('boundsJson сохраняет короткий диапазон через антимеридиан', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Dateline map',
        'dateline.ozf2',
        'IWH,Map Image Width/Height,1000,1000',
        'MMPNUM,4',
        'MMPXY,1,0,0',
        'MMPLL,1,179.0,10.0',
        'MMPXY,2,1000,0',
        'MMPLL,2,-179.0,10.0',
        'MMPXY,3,0,1000',
        'MMPLL,3,179.0,9.0',
        'MMPXY,4,1000,1000',
        'MMPLL,4,-179.0,9.0',
      ].join('\n');

      final bounds = OziMapParser.parseString(content).boundsAsMap!;
      expect(bounds['minLng'], closeTo(179.0, 0.0001));
      expect(bounds['maxLng'], closeTo(-179.0, 0.0001));
    });

    test('boundsJson возвращает null для пустых точек', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Empty Map',
        'empty.jpg',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'IWH,Map Image Width/Height,100,100',
        'MMPNUM,0',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.boundsJson, isNull);
      expect(result.points, isEmpty);
    });
  });

  group('OziMapParseResult — calibrationPointsJson', () {
    test('возвращает JSON массив с правильными полями', () {
      final content = _buildMMPLLContent();
      final result = OziMapParser.parseString(content);

      final json = result.calibrationPointsJson;
      expect(json, isNotNull);

      final list = jsonDecode(json!) as List<dynamic>;
      expect(list.length, 3);

      final first = list[0] as Map<String, dynamic>;
      expect(first.containsKey('pixelX'), true);
      expect(first.containsKey('pixelY'), true);
      expect(first.containsKey('lat'), true);
      expect(first.containsKey('lng'), true);
    });
  });

  group('OziMapParser — Windows-1251', () {
    test('parseBytes декодирует русские символы в Windows-1251', () {
      // Строка "Привет" в Windows-1251:
      // П=0xCF, р=0xF0, и=0xE8, в=0xE2, е=0xE5, т=0xF2
      // Строим всё содержимое как чистый cp1251 (ASCII-часть совпадает с UTF-8).
      const asciiHeader = 'OziExplorer Map Data File Version 2.1\r\n';
      final cp1251 = <int>[
        ...asciiHeader.codeUnits,
        0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, // Привет (название)
        0x0D, 0x0A, // \r\n
        ...'raster.png\r\n'.codeUnits,
        ...'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84\r\n'.codeUnits,
        ...'Reserved 1\r\n'.codeUnits,
        ...'Reserved 2\r\n'.codeUnits,
        ...'IWH,Map Image Width/Height,100,100\r\n'.codeUnits,
        ...'Point01,xy,50,50,in,deg,55,30.000,N,37,36.000,E, grid, , , ,\r\n'
            .codeUnits,
        ...'MMPNUM,1\r\n'.codeUnits,
      ];

      // Этот массив НЕ является валидным UTF-8 (из-за cp1251 байтов),
      // поэтому parseBytes переключится на Windows-1251.
      final result = OziMapParser.parseBytes(cp1251);
      expect(result.rasterPath, 'raster.png');
      expect(result.points.length, 1);
    });
  });

  group('OziMapParser — граничные случаи', () {
    test('пустой контент не вызывает ошибок', () {
      final result = OziMapParser.parseString('');
      expect(result.rasterPath, isNull);
      expect(result.points, isEmpty);
      expect(result.boundsJson, isNull);
    });

    test('контент только с заголовком', () {
      final result = OziMapParser.parseString(
        'OziExplorer Map Data File Version 2.1\n',
      );
      expect(result.rasterPath, isNull);
      expect(result.calibrationType, 'MMPLL');
    });

    test('несколько PointNN подряд (Point01..Point09)', () {
      final pts = List.generate(9, (i) {
        final n = (i + 1).toString().padLeft(2, '0');
        final x = 100 + i * 200;
        final y = 200 + i * 150;
        final latDeg = 55 + i;
        return 'Point$n,xy,$x,$y,in,deg,$latDeg,30.000,N,37,36.000,E, grid, , , ,';
      });

      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Multi-Point Map',
        'multi.jpg',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'IWH,Map Image Width/Height,3000,3000',
        ...pts,
        'MMPNUM,9',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      expect(result.points.length, 9);
    });

    test('игнорирует строка "Image File" с пустым путём', () {
      final content = [
        'OziExplorer Map Data File Version 2.1',
        'Empty Image File',
        '',
        'WGS 84,WGS 84,   0.0000,   0.0000,WGS 84',
        'Reserved 1',
        'Reserved 2',
        'Image File,',
        'IWH,Map Image Width/Height,100,100',
        'MMPNUM,0',
        '',
      ].join('\n');

      final result = OziMapParser.parseString(content);
      // rasterPath должен остаться null, потому что после "Image File," ничего нет.
      expect(result.rasterPath, isNull);
    });
  });
}
