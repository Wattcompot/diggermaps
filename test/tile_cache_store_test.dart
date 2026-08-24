import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:digger_maps/services/tile_cache/tile_cache_store.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('tile_cache_test_');
    PathProviderPlatform.instance = _FakePathProvider(temporaryDirectory.path);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('сохраняет и повторно читает тайл', () async {
    final cache = TileCacheStore(maxSizeBytes: 1024);
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    await cache.write('https://tiles.example/1/2/3.png', bytes);

    expect(await cache.read('https://tiles.example/1/2/3.png'), bytes);
    expect(await cache.read('https://tiles.example/missing.png'), isNull);
  });

  test('не возвращает просроченный тайл', () async {
    final cache = TileCacheStore(
      maxSizeBytes: 1024,
      maxAge: const Duration(milliseconds: 1),
    );
    const url = 'https://tiles.example/old.png';
    await cache.write(url, Uint8List.fromList(<int>[9]));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(await cache.read(url), isNull);
  });

  test('clear удаляет сохранённые тайлы', () async {
    final cache = TileCacheStore(maxSizeBytes: 1024);
    const url = 'https://tiles.example/clear.png';
    await cache.write(url, Uint8List.fromList(<int>[7, 8]));

    await cache.clear();

    expect(await cache.read(url), isNull);
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationCachePath() async => path;
}
