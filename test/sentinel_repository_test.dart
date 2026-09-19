import 'dart:convert';

import 'package:digger_maps/data/repositories/sentinel_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tileTemplateBase =
    'https://planetarycomputer.microsoft.com/api/data/v1/mosaic';

void main() {
  test('получает актуальный URL true-color тайлов из TileJSON', () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>[
        '{"searchid":"fresh-search-id"}',
        '{"tiles":["https://planetarycomputer.microsoft.com/api/data/v1/mosaic/fresh-search-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
      ],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = SentinelRepository(dio: dio);

    final url = await repository.getTileUrl(
      date: DateTime.utc(2026, 7, 29),
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.71538, 55.88921, 38.41850, 56.08617],
    );

    expect(adapter.options[0].path,
        'https://planetarycomputer.microsoft.com/api/data/v1/mosaic/register');
    expect(adapter.options[1].path,
        'https://planetarycomputer.microsoft.com/api/data/v1/mosaic/fresh-search-id/tilejson.json');
    expect(adapter.options[1].queryParameters['assets'], 'visual');
    expect(adapter.options[1].queryParameters['asset_bidx'], 'visual|1,2,3');
    expect(url, contains('/mosaic/fresh-search-id/tiles/WebMercatorQuad/'));
    expect(url, contains('{z}/{x}/{y}'));
    expect(url, isNot(contains('tiles.maps.eox.at')));
  });

  test('лимиты зума берутся из TileJSON, а не угадываются', () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>[
        '{"searchid":"zoomed-id"}',
        '{"tiles":["$_tileTemplateBase/zoomed-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"],"minzoom":4,"maxzoom":14}',
      ],
    );
    final repository =
        SentinelRepository(dio: Dio()..httpClientAdapter = adapter);

    final source = await repository.getTileSource(
      date: DateTime.utc(2026, 7, 20),
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.0, 55.0, 38.0, 56.0],
    );

    expect(source.minZoom, 4);
    expect(source.maxZoom, 14);
    expect(source.tileDimension, 256);
  });

  test('мозаика переиспользуется, пока bbox внутри покрытия', () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>[
        '{"searchid":"stable-id"}',
        '{"tiles":["$_tileTemplateBase/stable-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
      ],
    );
    final repository =
        SentinelRepository(dio: Dio()..httpClientAdapter = adapter);
    final date = DateTime.utc(2026, 7, 29);
    final dateTo = DateTime.utc(2026, 7, 30);

    final first = await repository.getTileSource(
      date: date,
      dateFrom: date,
      dateTo: dateTo,
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.0, 55.0, 38.0, 56.0],
    );
    // Панорама внутри покрытия: ни нового searchId, ни нового URL.
    final second = await repository.getTileSource(
      date: date,
      dateFrom: date,
      dateTo: dateTo,
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.3, 55.2, 37.9, 55.8],
    );

    final registers = adapter.options
        .where((options) => options.path.endsWith('/mosaic/register'));
    expect(registers, hasLength(1));
    expect(second.urlTemplate, first.urlTemplate);
    expect(adapter.options, hasLength(2));
  });

  test('bbox выравнивается наружу по устойчивой сетке (стабильный URL)',
      () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>[
        '{"searchid":"snapped-id"}',
        '{"tiles":["$_tileTemplateBase/snapped-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
      ],
    );
    final repository =
        SentinelRepository(dio: Dio()..httpClientAdapter = adapter);
    final date = DateTime.utc(2026, 7, 29);

    await repository.getTileSource(
      date: date,
      dateFrom: date,
      dateTo: DateTime.utc(2026, 7, 30),
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.71538, 55.88921, 38.41850, 56.08617],
    );

    final body =
        jsonDecode(adapter.requestBodies.first) as Map<String, dynamic>;
    final bbox =
        (body['bbox'] as List).cast<num>().map((v) => v.toDouble()).toList();
    // Шаг сетки 0.05°: bbox выравнивается наружу, а не «раздувается» на 25%.
    // Именно выравнивание (а не запас) делает URL устойчивым: слегка сдвинутые
    // окна дают тот же выровненный bbox.
    expect(bbox[0], closeTo(37.70, 1e-9));
    expect(bbox[1], closeTo(55.85, 1e-9));
    expect(bbox[2], closeTo(38.45, 1e-9));
    expect(bbox[3], closeTo(56.10, 1e-9));
  });

  test('bbox вне покрытия регистрирует новую мозаику', () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>[
        '{"searchid":"first-id"}',
        '{"tiles":["$_tileTemplateBase/first-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
        '{"searchid":"second-id"}',
        '{"tiles":["$_tileTemplateBase/second-id/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
      ],
    );
    final repository =
        SentinelRepository(dio: Dio()..httpClientAdapter = adapter);
    final date = DateTime.utc(2026, 7, 29);
    final dateTo = DateTime.utc(2026, 7, 30);

    final first = await repository.getTileSource(
      date: date,
      dateFrom: date,
      dateTo: dateTo,
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[37.0, 55.0, 38.0, 56.0],
    );
    final second = await repository.getTileSource(
      date: date,
      dateFrom: date,
      dateTo: dateTo,
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: const <double>[40.0, 55.0, 41.0, 56.0],
    );

    final registers = adapter.options
        .where((options) => options.path.endsWith('/mosaic/register'));
    expect(registers, hasLength(2));
    expect(first.urlTemplate, contains('first-id'));
    expect(second.urlTemplate, contains('second-id'));
  });

  test('кэш мозаик ограничен: старые записи вытесняются', () async {
    final bodies = <String>[];
    for (var index = 0; index < 80; index++) {
      bodies.add('{"searchid":"id-$index"}');
      bodies.add(
        '{"tiles":["$_tileTemplateBase/id-$index/tiles/WebMercatorQuad/{z}/{x}/{y}?assets=visual"]}',
      );
    }
    final adapter = _RecordingAdapter(responseBodies: bodies);
    final repository =
        SentinelRepository(dio: Dio()..httpClientAdapter = adapter);
    const bbox = <double>[37.0, 55.0, 38.0, 56.0];

    for (var day = 1; day <= 30; day++) {
      final date = DateTime.utc(2026, 6, day);
      await repository.getTileSource(
        date: date,
        dateFrom: date,
        dateTo: date.add(const Duration(days: 1)),
        cloudCoverage: 20,
        preset: SpectralPreset.naturalColor,
        bbox: bbox,
      );
    }
    final registersAfterFill = adapter.options
        .where((options) => options.path.endsWith('/mosaic/register'))
        .length;
    expect(registersAfterFill, 30);

    // Первая дата вытеснена из ограниченного кэша => регистрируем заново.
    final firstDate = DateTime.utc(2026, 6, 1);
    await repository.getTileSource(
      date: firstDate,
      dateFrom: firstDate,
      dateTo: firstDate.add(const Duration(days: 1)),
      cloudCoverage: 20,
      preset: SpectralPreset.naturalColor,
      bbox: bbox,
    );

    final registersAfterEviction = adapter.options
        .where((options) => options.path.endsWith('/mosaic/register'))
        .length;
    expect(registersAfterEviction, 31);
  });

  test('поиск дат запрашивает сначала самые свежие снимки', () async {
    final adapter = _RecordingAdapter(
      responseBodies: <String>['{"features":[]}'],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = SentinelRepository(dio: dio);

    await repository.queryDates(
      bbox: const <double>[37.71538, 55.88921, 38.41850, 56.08617],
      from: DateTime.utc(2026, 7, 1),
      to: DateTime.utc(2026, 7, 30),
    );

    final body = jsonDecode(adapter.requestBody!) as Map<String, dynamic>;
    final sort = (body['sortby'] as List).single as Map<String, dynamic>;
    expect(sort['field'], 'properties.datetime');
    expect(sort['direction'], 'desc');
    final fields = body['fields'] as Map<String, dynamic>;
    expect(
      fields['include'],
      containsAll(<String>[
        'properties.datetime',
        'properties.eo:cloud_cover',
      ]),
    );
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responseBodies});

  final List<String> responseBodies;
  final List<RequestOptions> options = <RequestOptions>[];
  final List<String> requestBodies = <String>[];
  String? requestBody;

  RequestOptions? get lastOptions => options.isEmpty ? null : options.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions requestOptions,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    options.add(requestOptions);
    if (requestStream != null) {
      final body = utf8.decode(
        await requestStream.expand((chunk) => chunk).toList(),
      );
      requestBody = body;
      requestBodies.add(body);
    }
    final responseBody = responseBodies[options.length - 1];
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
