import 'dart:convert';

import 'package:digger_maps/data/repositories/sentinel_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
      requestBody = utf8.decode(
        await requestStream.expand((chunk) => chunk).toList(),
      );
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
