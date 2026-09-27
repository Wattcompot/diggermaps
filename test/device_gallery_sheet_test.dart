import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/presentation/widgets/app_scroll.dart';
import 'package:digger_maps/presentation/widgets/media/device_gallery_sheet.dart';
import 'package:digger_maps/presentation/widgets/media/marker_media_section.dart';
import 'package:digger_maps/services/media/marker_media_service.dart';
import 'package:digger_maps/services/media/marker_media_store.dart';

/// Элемент галереи без платформенного плагина.
class _FakeAsset implements DeviceGalleryAsset {
  const _FakeAsset({
    required this.id,
    required this.path,
    this.isVideo = false,
    this.duration,
  });

  @override
  final String id;
  final String path;

  @override
  final bool isVideo;

  @override
  final Duration? duration;

  @override
  Future<Uint8List?> thumbnailData(int extent) async => null;

  @override
  Future<String?> resolvePath() async => path;
}

/// Источник с заранее заданным содержимым: проверяем сам экран галереи.
class _FakeSource implements DeviceGallerySource {
  _FakeSource({
    this.access = DeviceGalleryAccess.granted,
    this.photos = const <DeviceGalleryAsset>[],
    this.videos = const <DeviceGalleryAsset>[],
  });

  final DeviceGalleryAccess access;
  final List<DeviceGalleryAsset> photos;
  final List<DeviceGalleryAsset> videos;

  int openSettingsCalls = 0;
  final List<bool> requestedVideoOnly = <bool>[];

  @override
  Future<DeviceGalleryAccess> ensureAccess() async => access;

  @override
  Future<List<DeviceGalleryAsset>> loadPage({
    required int page,
    required int pageSize,
    required bool videoOnly,
  }) async {
    requestedVideoOnly.add(videoOnly);
    if (page > 0) return const <DeviceGalleryAsset>[];
    return videoOnly ? videos : photos;
  }

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}

Future<void> _openSheet(
  WidgetTester tester,
  DeviceGallerySource source, {
  bool initialVideo = false,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    scrollBehavior: appScrollBehavior,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => DeviceGallerySheet.show(
              context,
              source: source,
              initialVideo: initialVideo,
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('показывает сетку фото и выбирает несколько файлов',
      (tester) async {
    final source = _FakeSource(
      photos: const <DeviceGalleryAsset>[
        _FakeAsset(id: '1', path: r'C:\media\a.jpg'),
        _FakeAsset(id: '2', path: r'C:\media\b.jpg'),
        _FakeAsset(id: '3', path: r'C:\media\c.jpg'),
      ],
    );
    await _openSheet(tester, source);

    expect(find.text('Галерея'), findsOneWidget);
    expect(find.text('Ничего не выбрано'), findsOneWidget);
    expect(source.requestedVideoOnly, <bool>[false]);

    // Выбираем два файла: нумерация появляется по порядку выбора.
    await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-2')));
    await tester.pump();

    expect(find.text('Выбрано: 2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Тап по выбранному снимает выбор.
    await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-1')));
    await tester.pump();
    expect(find.text('Выбрано: 1'), findsOneWidget);
  });

  testWidgets('кнопка «Добавить» отдаёт выбранные пути', (tester) async {
    final source = _FakeSource(
      photos: const <DeviceGalleryAsset>[
        _FakeAsset(id: '1', path: r'C:\media\a.jpg'),
        _FakeAsset(id: '2', path: r'C:\media\b.jpg'),
      ],
    );
    List<DeviceGalleryPick>? result;

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      scrollBehavior: appScrollBehavior,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await DeviceGallerySheet.show(context, source: source);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-2')));
    await tester.pump();
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 1);
    expect(result!.single.path, r'C:\media\b.jpg');
    expect(result!.single.isVideo, isFalse);
  });

  testWidgets('вкладка «Видео» показывает длительность и отдаёт признак видео',
      (tester) async {
    final source = _FakeSource(
      photos: const <DeviceGalleryAsset>[
        _FakeAsset(id: 'p1', path: r'C:\media\a.jpg'),
      ],
      videos: const <DeviceGalleryAsset>[
        _FakeAsset(
          id: 'v1',
          path: r'C:\media\clip.mp4',
          isVideo: true,
          duration: Duration(seconds: 95),
        ),
      ],
    );
    await _openSheet(tester, source, initialVideo: true);

    // Открылись сразу на видео: фото-альбом не запрашивался.
    expect(source.requestedVideoOnly, <bool>[true]);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('01:35'), findsOneWidget);

    // Переключение на фото и обратно меняет набор.
    await tester.tap(find.text('Фото'));
    await tester.pumpAndSettle();
    expect(source.requestedVideoOnly, <bool>[true, false]);
    expect(find.text('01:35'), findsNothing);
  });

  testWidgets('без доступа объясняет и предлагает настройки', (tester) async {
    final source = _FakeSource(access: DeviceGalleryAccess.denied);
    await _openSheet(tester, source);

    expect(find.text('Нет доступа к галерее устройства'), findsOneWidget);
    expect(find.text('Добавить'), findsOneWidget);
    // Кнопка «Добавить» неактивна: выбирать нечего.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Добавить'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Открыть настройки'));
    await tester.pump();
    expect(source.openSettingsCalls, 1);
  });

  testWidgets('пустая медиатека показывает понятный текст', (tester) async {
    await _openSheet(tester, _FakeSource());

    expect(find.text('На устройстве нет фото'), findsOneWidget);
  });

  test('миниатюра-заглушка не используется в проверках декодирования', () {
    // Пустая миниатюра — это именно placeholder-ветка сетки; декодирование
    // реальных изображений проверяется приложением, а не этим экраном.
    const asset = _FakeAsset(id: 'x', path: 'x.jpg');
    expect(asset.isVideo, isFalse);
  });

  group('MarkerMediaSection: встроенная галерея', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('digger_gallery');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// Сервис, который считает себя Android-устройством с доступной галереей.
    _GalleryAwareService serviceFor() =>
        _GalleryAwareService(store: MarkerMediaStore(documentsDirectory: root));

    /// Пока открыт лист галереи, секция медиа показывает индикатор занятости —
    /// его анимация бесконечна, поэтому `pumpAndSettle` здесь не годится:
    /// прокручиваем фиксированное число кадров.
    Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('кнопка «Фото» открывает галерею и добавляет выбранное',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final service = serviceFor();
      final source = _FakeSource(
        photos: const <DeviceGalleryAsset>[
          _FakeAsset(id: 'g1', path: r'C:\gallery\from_gallery.jpg'),
        ],
      );

      List<MarkerMedia>? changed;
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: Scaffold(
          body: MarkerMediaSection(
            media: const <MarkerMedia>[],
            service: service,
            gallerySource: source,
            onChanged: (value) => changed = value,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Фото'));
      await pumpFrames(tester);

      // Открылась ВСТРОЕННАЯ галерея приложения, а не системный пикер:
      // сетка с заголовком и элементами источника.
      expect(find.text('Галерея'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-g1')));
      await tester.pump();
      await tester.tap(find.text('Добавить'));
      await pumpFrames(tester);

      expect(changed, isNotNull);
      expect(changed!.length, 1);
      expect(changed!.single.isPhoto, isTrue);
      // Импортирован именно путь из галереи, а не из системного выбора файла.
      expect(service.importedPaths, <String>[r'C:\gallery\from_gallery.jpg']);
    });

    testWidgets('кнопка «Видео» открывает галерею сразу на видео',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final service = serviceFor();
      final source = _FakeSource(
        videos: const <DeviceGalleryAsset>[
          _FakeAsset(
            id: 'v1',
            path: r'C:\gallery\from_gallery.mp4',
            isVideo: true,
            duration: Duration(seconds: 12),
          ),
        ],
      );

      List<MarkerMedia>? changed;
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: Scaffold(
          body: MarkerMediaSection(
            media: const <MarkerMedia>[],
            service: service,
            gallerySource: source,
            onChanged: (value) => changed = value,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Видео'));
      await pumpFrames(tester);

      expect(find.text('Галерея'), findsOneWidget);
      expect(source.requestedVideoOnly, <bool>[true],
          reason: 'Кнопка «Видео» открывает вкладку видео');

      await tester.tap(find.byKey(const ValueKey<String>('gallery-tile-v1')));
      await tester.pump();
      await tester.tap(find.text('Добавить'));
      await pumpFrames(tester);

      expect(changed, isNotNull);
      expect(changed!.single.isVideo, isTrue);
      expect(changed!.single.mimeType, 'video/mp4');
      expect(service.importedPaths, <String>[r'C:\gallery\from_gallery.mp4']);
    });
  });
}

/// Сервис, который ведёт себя как Android-устройство с доступной галереей.
///
/// Импорт переопределён: тест проверяет маршрут выбора (галерея вместо
/// системного пикера) и состав добавленных вложений, а реальное копирование
/// файлов покрыто `marker_media_store_test` и
/// `user_marker_repository_media_test`. Так тест остаётся герметичным:
/// виджету не нужен настоящий event loop для файловых операций.
class _GalleryAwareService extends MarkerMediaService {
  _GalleryAwareService({required super.store});

  final List<String> importedPaths = <String>[];

  @override
  bool get supported => true;

  @override
  bool get inAppGallerySupported => true;

  @override
  bool get cameraSupported => false;

  @override
  Future<MarkerMedia?> pickPhoto({bool camera = false}) async {
    fail('Системный пикер не должен вызываться: есть встроенная галерея');
  }

  @override
  Future<MarkerMedia?> pickVideo({bool camera = false}) async {
    fail('Системный пикер не должен вызываться: есть встроенная галерея');
  }

  @override
  Future<MarkerMedia> importPhoto(String sourcePath) async {
    importedPaths.add(sourcePath);
    return MarkerMedia(
      fileRef: 'marker_media/${importedPaths.length}_photo.jpg',
      type: MarkerMedia.typePhoto,
      name: p.basename(sourcePath),
      mimeType: 'image/jpeg',
      createdAt: DateTime(2026, 4, 1),
      bytes: 128,
    );
  }

  @override
  Future<MarkerMedia> importVideo(String sourcePath, {int? durationMs}) async {
    importedPaths.add(sourcePath);
    return MarkerMedia(
      fileRef: 'marker_media/${importedPaths.length}_video.mp4',
      type: MarkerMedia.typeVideo,
      name: p.basename(sourcePath),
      mimeType: 'video/mp4',
      createdAt: DateTime(2026, 4, 1),
      bytes: 256,
      durationMs: durationMs,
    );
  }
}
