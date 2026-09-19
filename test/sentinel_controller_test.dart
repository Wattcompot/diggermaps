import 'package:digger_maps/data/repositories/sentinel_repository.dart';
import 'package:digger_maps/presentation/providers/sentinel_controller.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const String _urlOne = 'https://example.test/mosaic/one/{z}/{x}/{y}';
const String _urlTwo = 'https://example.test/mosaic/two/{z}/{x}/{y}';

class _FakeSentinelRepository extends SentinelRepository {
  String tileUrlTemplate = _urlOne;
  int? maxZoom = 14;
  Object? failure;
  int tileSourceRequests = 0;

  @override
  Future<SentinelTileSource> getTileSource({
    required DateTime date,
    required double cloudCoverage,
    required SpectralPreset preset,
    DateTime? dateFrom,
    DateTime? dateTo,
    required List<double> bbox,
  }) async {
    tileSourceRequests++;
    final error = failure;
    if (error != null) throw error;
    return SentinelTileSource(
      urlTemplate: tileUrlTemplate,
      minZoom: 0,
      maxZoom: maxZoom,
    );
  }
}

SentinelController _controller(_FakeSentinelRepository repository) {
  return SentinelController(
    visibleBounds: () =>
        LatLngBounds(const LatLng(55.0, 37.0), const LatLng(56.0, 38.0)),
    repository: repository,
    onError: (_) {},
    retainedImageryTtl: const Duration(milliseconds: 300),
    retainedImageryGrace: const Duration(milliseconds: 20),
  );
}

void main() {
  test('провайдер и слой переиспользуются при том же URL', () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    final provider = controller.tileProvider;

    await controller.applyDate(DateTime.utc(2026, 7, 29));
    expect(controller.tileUrl, _urlOne);
    expect(controller.imagery!.maxNativeZoom, 14);
    expect(controller.layerVersion, 1);

    await controller.applyDate(DateTime.utc(2026, 7, 29));
    expect(identical(controller.tileProvider, provider), isTrue);
    expect(controller.layerVersion, 1);
    expect(controller.retainedImagery, isNull);

    controller.dispose();
  });

  test('смена URL той же даты удерживает предыдущую картинку', () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    await controller.applyDate(DateTime.utc(2026, 7, 29));
    final firstId = controller.imagery!.id;

    // Панорама вышла за покрытие: тот же день, другая мозаика.
    repository.tileUrlTemplate = _urlTwo;
    await controller.refreshTile();

    expect(controller.imagery!.id, isNot(firstId));
    expect(controller.retainedImagery!.id, firstId);
    expect(controller.layerVersion, 1, reason: 'дата не менялась');
    expect(controller.loading, isTrue);
    expect(controller.imageryDisplayed, isFalse);
    expect(controller.imageryDate, DateTime(2026, 7, 29));

    controller.markImageryDisplayed();
    expect(controller.loading, isFalse);
    expect(controller.imageryDisplayed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.retainedImagery, isNull,
        reason: 'retained снимается после grace-периода');

    controller.dispose();
  });

  test('новая дата не подписывает предыдущую картинку', () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    await controller.applyDate(DateTime.utc(2026, 7, 29));

    repository.tileUrlTemplate =
        'https://example.test/mosaic/july30/{z}/{x}/{y}';
    final pending = controller.applyDate(DateTime.utc(2026, 7, 30));

    // Выбрана новая дата, но на карте всё ещё прежняя картинка.
    expect(controller.date, DateTime.utc(2026, 7, 30));
    expect(controller.imageryDate, DateTime(2026, 7, 29));
    expect(controller.loading, isTrue);
    expect(controller.retainedImagery, isNull);

    await pending;
    expect(controller.imageryDate, DateTime(2026, 7, 30));
    expect(controller.retainedImagery!.dateKey, '2026-07-29');
    expect(controller.layerVersion, 2);

    controller.dispose();
  });

  test('retained ограничен таймаутом, если новая картинка не отрисовалась',
      () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    await controller.applyDate(DateTime.utc(2026, 7, 29));

    repository.tileUrlTemplate = _urlTwo;
    await controller.refreshTile();
    expect(controller.retainedImagery, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(controller.retainedImagery, isNull);
    expect(controller.imageryDisplayed, isFalse,
        reason: 'честный прогресс: тайл не загрузился');

    controller.dispose();
  });

  test('ошибка не подменяет уже показанную картинку', () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    await controller.applyDate(DateTime.utc(2026, 7, 29));

    repository.failure = NoImageryException('нет снимков');
    await controller.applyDate(DateTime.utc(2026, 7, 30));

    expect(controller.imagery!.dateKey, '2026-07-29');
    expect(controller.imageryDate, DateTime(2026, 7, 29));
    expect(controller.loading, isFalse);

    controller.dispose();
  });

  test('hideImagery очищает и текущий, и удержанный слой', () async {
    final repository = _FakeSentinelRepository();
    final controller = _controller(repository);
    await controller.applyDate(DateTime.utc(2026, 7, 29));
    repository.tileUrlTemplate = _urlTwo;
    await controller.refreshTile();
    expect(controller.retainedImagery, isNotNull);

    controller.hideImagery();

    expect(controller.visible, isFalse);
    expect(controller.tileUrl, isNull);
    expect(controller.retainedImagery, isNull);
    expect(controller.imageryDisplayed, isFalse);
    expect(controller.loading, isFalse);

    controller.dispose();
  });
}
