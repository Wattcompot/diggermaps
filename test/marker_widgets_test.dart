import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/data/models/user_marker.dart';
import 'package:digger_maps/presentation/widgets/bottom_sheets/marker_bottom_sheet.dart';
import 'package:digger_maps/presentation/widgets/bottom_sheets/marker_create_dialog.dart';
import 'package:digger_maps/presentation/widgets/media/marker_media_section.dart';
import 'package:digger_maps/presentation/widgets/media/marker_voice_player.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_preview_card.dart';
import 'package:digger_maps/presentation/widgets/poi/user_marker_layer.dart';
import 'package:digger_maps/services/media/marker_media_service.dart';
import 'package:digger_maps/services/media/marker_media_store.dart';

/// Сервис, который на этой платформе ничего не умеет: проверяем подсказку
/// вместо кнопок, без обращения к плагинам.
class _UnsupportedMediaService extends MarkerMediaService {
  _UnsupportedMediaService({required super.store});

  @override
  bool get supported => false;
}

/// Уборка черновиков идёт из `dispose` и состоит из цепочки реальных файловых
/// операций. Под FakeAsync (тестовые таймеры) её нужно чередовать: реальное
/// время для ввода-вывода и `pump` для продолжений в тестовой зоне.
Future<void> drainCleanup(WidgetTester tester) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

MarkerMedia voiceMedia([String ref = 'marker_media/9_voice.wav']) =>
    MarkerMedia(
      fileRef: ref,
      type: MarkerMedia.typeVoice,
      name: 'Голосовая заметка.wav',
      mimeType: 'audio/wav',
      createdAt: DateTime(2026, 4, 1),
      durationMs: 5000,
    );

void main() {
  late Directory root;
  late MarkerMediaStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('digger_widgets');
    store = MarkerMediaStore(documentsDirectory: root);
  });

  tearDown(() {
    // Windows держит дескриптор декодированного Image.file, пока живёт запись в
    // кэше изображений, поэтому временную папку удаляем только после чистки.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Системный временный каталог ОС уберёт сама.
    }
  });

  /// Корректный PNG 1x1: миниатюра реально декодируется, поэтому тест не
  /// падает на ошибке кодека изображений.
  const png1x1 = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
    0x42, 0x60, 0x82,
  ];

  File sourcePhoto(String name) => File(p.join(root.path, name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(png1x1);

  /// Черновик-запись: управляемый файл без отрисовки, поэтому проверяем именно
  /// логику очистки, а не блокировку файла декодером изображений.
  Future<MarkerMedia> importVoice(String name) async {
    final ref = await store.allocate('wav');
    final file = (await store.resolve(ref))!;
    file.writeAsBytesSync(List<int>.filled(64, 1));
    return MarkerMedia(
      fileRef: ref,
      type: MarkerMedia.typeVoice,
      name: name,
      mimeType: 'audio/wav',
      createdAt: DateTime(2026, 4, 1),
      bytes: 64,
      durationMs: 3000,
    );
  }

  group('MarkerPreviewCard', () {
    testWidgets('показывает название и описание и открывает редактор',
        (tester) async {
      var opened = 0;
      var closed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: MarkerPreviewCard(
              marker: UserMarker(
                id: 1,
                name: 'Яма',
                description: 'Глубокая',
                lat: 0,
                lng: 0,
                colorHex: '#FF0000',
                media: <MarkerMedia>[voiceMedia()],
              ),
              onTap: () => opened++,
              onClose: () => closed++,
            ),
          ),
        ),
      ));

      expect(find.text('Яма'), findsOneWidget);
      expect(find.text('Глубокая'), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

      await tester.tap(find.text('Яма'));
      await tester.pump();
      expect(opened, 1);
      expect(closed, 0);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('описание скрывается, когда его нет', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkerPreviewCard(
            marker: UserMarker(
              id: 2,
              name: 'Без описания',
              lat: 0,
              lng: 0,
              colorHex: '#FF0000',
            ),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('Без описания'), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
    });
  });

  group('UserMarkerLayer: первый и второй тап', () {
    Future<List<UserMarker>> pumpLayer(WidgetTester tester) async {
      final taps = <UserMarker>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(0, 0),
              initialZoom: 15,
            ),
            children: <Widget>[
              UserMarkerLayer(
                markers: <UserMarker>[
                  UserMarker(
                    id: 1,
                    name: 'Яма',
                    description: 'Глубокая',
                    lat: 0,
                    lng: 0,
                    colorHex: '#FF0000',
                    size: 32,
                  ),
                ],
                selectedMarkerId: null,
                onMarkerTap: taps.add,
                onMarkerLongPress: taps.add,
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return taps;
    }

    testWidgets('первый тап — карточка, тап по карточке — редактор',
        (tester) async {
      final taps = await pumpLayer(tester);
      final glyph = find.byKey(const ValueKey<String>('marker-1'));
      expect(glyph, findsOneWidget);
      expect(find.text('Яма'), findsNothing);

      await tester.tap(glyph);
      await tester.pumpAndSettle();

      // Карточка появилась, редактор ещё не открыт.
      expect(find.text('Яма'), findsOneWidget);
      expect(find.text('Глубокая'), findsOneWidget);
      expect(taps, isEmpty);

      await tester.tap(find.text('Яма'));
      await tester.pumpAndSettle();
      expect(taps.length, 1);
      expect(taps.single.name, 'Яма');
      // После открытия редактора карточка скрыта.
      expect(find.text('Глубокая'), findsNothing);
    });

    testWidgets('повторный тап по метке скрывает карточку', (tester) async {
      final taps = await pumpLayer(tester);
      final glyph = find.byKey(const ValueKey<String>('marker-1'));
      await tester.tap(glyph);
      await tester.pumpAndSettle();
      expect(find.text('Яма'), findsOneWidget);

      await tester.tapAt(tester.getCenter(glyph) + const Offset(0, 6));
      await tester.pumpAndSettle();
      expect(find.text('Яма'), findsNothing);
      expect(taps, isEmpty);
    });

    testWidgets('долгое нажатие открывает редактор сразу', (tester) async {
      final taps = await pumpLayer(tester);
      await tester.longPress(find.byKey(const ValueKey<String>('marker-1')));
      await tester.pumpAndSettle();
      expect(taps.length, 1);
      expect(find.text('Глубокая'), findsNothing);
    });
  });

  group('MarkerMediaSection', () {
    testWidgets('пустое состояние и подсказка на неподдерживаемой платформе',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkerMediaSection(
            media: const <MarkerMedia>[],
            service: _UnsupportedMediaService(store: store),
            onChanged: (_) {},
          ),
        ),
      ));

      expect(
        find.text('Видео'),
        findsOneWidget,
      );
      expect(
          find.text('Вложения доступны на Android и Windows'), findsOneWidget);
      final gallery = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Фото'),
      );
      expect(gallery.onPressed, isNull);
    });

    testWidgets('голосовая заметка удаляется из списка без удаления файла',
        (tester) async {
      final media = voiceMedia();
      List<MarkerMedia>? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkerMediaSection(
            media: <MarkerMedia>[media],
            service: MarkerMediaService(store: store),
            onChanged: (value) => changed = value,
          ),
        ),
      ));

      expect(find.byType(MarkerVoicePlayer), findsOneWidget);
      expect(find.text('Голосовая заметка.wav'), findsNothing);
      expect(find.text('00:00 / 00:05'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed!, isEmpty);
      expect(find.text('Голосовая заметка.wav'), findsNothing);
    });

    testWidgets('черновик сессии сразу удаляется с диска', (tester) async {
      final added = await tester.runAsync(
        () => store.importPhoto(sourcePhoto('draft.png').path),
      );
      expect(added, isNotNull);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkerMediaSection(
            media: const <MarkerMedia>[],
            service: MarkerMediaService(store: store),
            onChanged: (_) {},
          ),
        ),
      ));
      final state = tester
          .state<MarkerMediaSectionState>(find.byType(MarkerMediaSection));
      state.addImportedMedia(added!);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsNothing);
      await drainCleanup(tester);
      final exists = await tester.runAsync(() => store.exists(added.fileRef));

      expect(exists, isFalse);
    });
  });

  group('MarkerBottomSheet: черновики', () {
    UserMarker marker({List<MarkerMedia> media = const <MarkerMedia>[]}) =>
        UserMarker(
          id: 5,
          name: 'Яма',
          description: 'Глубокая',
          lat: 0,
          lng: 0,
          colorHex: '#FF0000',
          media: media,
        );

    Widget sheet(MarkerMediaService service, UserMarker value) => MaterialApp(
          home: Scaffold(
            body: MarkerBottomSheet(
              marker: value,
              onDelete: (_) async => false,
              onStyle: (_) async => null,
              onShare: () {},
              onExport: () {},
              onCopyCoordinates: () {},
              onNavigation: () {},
              onDirection: () {},
              mediaService: service,
            ),
          ),
        );

    testWidgets('отмена редактирования удаляет только новые файлы',
        (tester) async {
      final imported = await tester.runAsync(() async {
        final saved = await store.importPhoto(sourcePhoto('saved.png').path);
        final draft = await importVoice('draft.wav');
        return (saved: saved, draft: draft);
      });
      final value = marker(media: <MarkerMedia>[imported!.saved]);

      await tester.pumpWidget(sheet(MarkerMediaService(store: store), value));
      final state = tester
          .state<MarkerMediaSectionState>(find.byType(MarkerMediaSection));
      state.addImportedMedia(imported.draft);
      await tester.pump();
      expect(find.byType(MarkerVoicePlayer), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      // Закрываем редактор без «Готово» — сессия не подтверждена.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await drainCleanup(tester);

      final draftExists =
          await tester.runAsync(() => store.exists(imported.draft.fileRef));
      final savedExists =
          await tester.runAsync(() => store.exists(imported.saved.fileRef));

      expect(draftExists, isFalse);
      expect(savedExists, isTrue);
    });

    testWidgets('сохранённые вложения остаются после отмены', (tester) async {
      final saved = await tester.runAsync(
        () => store.importPhoto(sourcePhoto('keep.png').path),
      );
      await tester.pumpWidget(
        sheet(MarkerMediaService(store: store), marker(media: [saved!])),
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await drainCleanup(tester);

      final exists = await tester.runAsync(() => store.exists(saved.fileRef));
      expect(exists, isTrue);
    });
  });

  group('MarkerCreateDialog: медиа при создании', () {
    testWidgets('выбранное вложение попадает в MarkerCreateSelection',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      MarkerCreateSelection? result;
      final service = MarkerMediaService(store: store);
      final draft = await tester.runAsync(
        () => store.importPhoto(sourcePhoto('new.png').path),
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await MarkerCreateDialog.show(
                    context,
                    point: const LatLng(1, 2),
                    previewBuilder: (_, __, ___) => const SizedBox.shrink(),
                    mediaService: service,
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      tester
          .state<MarkerMediaSectionState>(find.byType(MarkerMediaSection))
          .addImportedMedia(draft!);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Новая метка');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.name, 'Новая метка');
      expect(result!.media.length, 1);
      expect(result!.media.single.fileRef, draft.fileRef);

      final exists = await tester.runAsync(() => store.exists(draft.fileRef));
      expect(exists, isTrue, reason: 'созданная метка владеет вложением');
    });

    testWidgets('отмена создания удаляет черновик', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final draft = await tester.runAsync(() => importVoice('cancel.wav'));
      final service = MarkerMediaService(store: store);
      MarkerCreateSelection? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await MarkerCreateDialog.show(
                    context,
                    point: const LatLng(1, 2),
                    previewBuilder: (_, __, ___) => const SizedBox.shrink(),
                    mediaService: service,
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      tester
          .state<MarkerMediaSectionState>(find.byType(MarkerMediaSection))
          .addImportedMedia(draft!);
      await tester.pump();

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await drainCleanup(tester);

      expect(result, isNull);
      final exists = await tester.runAsync(() => store.exists(draft.fileRef));
      expect(exists, isFalse);
    });
  });
}
