import 'package:digger_maps/data/models/wikimapia_models.dart';
import 'package:digger_maps/data/repositories/wikimapia_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('текстовые теги фильтруются локально по названию и категориям', () {
    final places = <WikimapiaPlace>[
      _place(
        id: 1,
        title: 'Урочище Лесное',
        description: 'Заброшенная деревня',
        categories: const <String>['Исторический объект'],
      ),
      _place(
        id: 2,
        title: 'Озеро',
        description: 'Место для рыбалки',
        categories: const <String>['Водоём'],
      ),
    ];

    final filtered = WikimapiaRepository.filterPlaces(places, const ['уроч']);

    expect(filtered.map((place) => place.id), <int>[1]);
  });

  test('запрос области не передаёт текст как category и не ставит User-Agent',
      () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = WikimapiaRepository(dio: dio);

    await repository.getPlacesByArea(
      bounds: LatLngBounds(
        const LatLng(55.88921, 37.71538),
        const LatLng(56.08617, 38.41850),
      ),
    );

    final options = adapter.lastOptions!;
    expect(options.queryParameters.containsKey('category'), isFalse);
    expect(options.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('user-agent')));
    expect(options.uri.scheme, 'https');
  });

  test('пустой bbox использует tile fallback', () async {
    final adapter = _SequenceAdapter(<String>[
      '[]',
      '[{"id":42,"title":"Объект","location":{"lat":55.75,"lon":37.62}}]',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = WikimapiaRepository(dio: dio);

    final places = await repository.getPlacesByArea(
      bounds: LatLngBounds(
        const LatLng(55.72, 37.58),
        const LatLng(55.79, 37.68),
      ),
    );

    expect(places.single.id, 42);
    expect(adapter.options, hasLength(2));
    expect(adapter.options[1].queryParameters, containsPair('z', 8));
    expect(adapter.options[1].queryParameters, contains('x'));
    expect(adapter.options[1].queryParameters, contains('y'));
  });

  test('код 1004 преобразуется в понятную ошибку лимита', () async {
    final adapter = _SequenceAdapter(<String>[
      '{"debug":{"code":1004,"message":"Key limit has been reached"}}',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = WikimapiaRepository(dio: dio);

    expect(
      () => repository.getPlacesByArea(
        bounds: LatLngBounds(
          const LatLng(55.72, 37.58),
          const LatLng(55.79, 37.68),
        ),
      ),
      throwsA(isA<WikimapiaApiLimitException>()),
    );
  });
}

WikimapiaPlace _place({
  required int id,
  required String title,
  required String description,
  required List<String> categories,
}) {
  return WikimapiaPlace(
    id: id,
    title: title,
    description: description,
    categories: categories
        .map((title) => WikimapiaCategory(id: id, title: title))
        .toList(),
    polygon: const <LatLng>[],
    location: const LatLng(55.95, 38.0),
    url: '',
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      '{"folder":[]}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<String> responses;
  final List<RequestOptions> options = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions requestOptions,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    options.add(requestOptions);
    final index = options.length - 1;
    return ResponseBody.fromString(
      responses[index.clamp(0, responses.length - 1)],
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
