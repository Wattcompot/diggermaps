import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/data/models/user_marker.dart';
import 'package:digger_maps/data/repositories/marker_json_store.dart';
import 'package:digger_maps/data/repositories/user_marker_repository.dart';
import 'package:digger_maps/services/media/marker_media_store.dart';

/// Windows-путь репозитория (JSON-хранилище) — тот же код, что работает в
/// приложении, но с временной папкой вместо documents.
void main() {
  late Directory root;
  late MarkerMediaStore mediaStore;
  late UserMarkerRepository repository;
  late File storeFile;

  setUp(() {
    root = Directory.systemTemp.createTempSync('digger_repo');
    storeFile = File(p.join(root.path, 'user_markers.json'));
    mediaStore = MarkerMediaStore(documentsDirectory: root);
    repository = UserMarkerRepository(
      jsonStore: MarkerJsonStore(directory: root),
      mediaStore: mediaStore,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File sourcePhoto(String name) => File(p.join(root.path, name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(List<int>.filled(64, 3));

  UserMarker markerWith({
    required String name,
    List<MarkerMedia> media = const <MarkerMedia>[],
    int minute = 0,
  }) =>
      UserMarker(
        name: name,
        description: 'описание',
        lat: 55.75,
        lng: 37.61,
        colorHex: '#A67B5B',
        size: 32,
        createdAt: DateTime(2026, 4, 1, 12, minute),
        media: media,
      );

  group('CRUD вложений через JSON-хранилище', () {
    test('вложения сохраняются как ссылки, а не как содержимое', () async {
      final media = await mediaStore.importPhoto(sourcePhoto('a.jpg').path);
      final id =
          await repository.create(markerWith(name: 'Яма', media: [media]));

      expect(id, 1);
      final raw = await storeFile.readAsString();
      expect(raw, contains('marker_media/'));
      expect(raw, contains('media_json'));
      expect(raw.contains('base64'), isFalse);
      expect(raw.length, lessThan(1200));

      final loaded = await repository.read(id);
      expect(loaded, isNotNull);
      expect(loaded!.media.length, 1);
      expect(loaded.media.single.fileRef, media.fileRef);
      expect(loaded.hasMedia, isTrue);
    });

    test('метка без вложений и старые записи читаются', () async {
      await repository.create(markerWith(name: 'Без медиа'));
      final loaded = (await repository.getAll()).single;
      expect(loaded.media, isEmpty);
      expect(loaded.name, 'Без медиа');
    });

    test('порядок выдачи — от новых к старым', () async {
      await repository.create(markerWith(name: 'старая', minute: 1));
      await repository.create(markerWith(name: 'новая', minute: 2));
      final all = await repository.getAll();
      expect(all.map((marker) => marker.name), <String>['новая', 'старая']);
    });
  });

  group('очистка файлов', () {
    test('снятое вложение удаляется после успешного сохранения', () async {
      final media = await mediaStore.importPhoto(sourcePhoto('a.jpg').path);
      final id = await repository.create(markerWith(name: 'A', media: [media]));
      expect(await mediaStore.exists(media.fileRef), isTrue);

      final saved = (await repository.read(id))!;
      final count = await repository.update(saved.copyWith(media: const []));

      expect(count, 1);
      expect(await mediaStore.exists(media.fileRef), isFalse);
      expect((await repository.read(id))!.media, isEmpty);
    });

    test('вложение остаётся, пока на него ссылается та же метка', () async {
      final media = await mediaStore.importPhoto(sourcePhoto('a.jpg').path);
      final id = await repository.create(markerWith(name: 'A', media: [media]));
      final saved = (await repository.read(id))!;

      await repository.update(saved.copyWith(name: 'A2'));

      expect(await mediaStore.exists(media.fileRef), isTrue);
    });

    test('удаление метки удаляет её файлы и не трогает файлы других меток',
        () async {
      final first = await mediaStore.importPhoto(sourcePhoto('a.jpg').path);
      final second = await mediaStore.importPhoto(sourcePhoto('b.jpg').path);
      final firstId =
          await repository.create(markerWith(name: 'A', media: [first]));
      await repository.create(markerWith(name: 'B', media: [second]));

      expect(await repository.delete(firstId), 1);

      expect(await mediaStore.exists(first.fileRef), isFalse);
      expect(await mediaStore.exists(second.fileRef), isTrue);
      expect((await repository.getAll()).single.name, 'B');
    });

    test('файлы метки не удаляются, если сохранение не состоялось', () async {
      final media = await mediaStore.importPhoto(sourcePhoto('a.jpg').path);
      final orphan = UserMarker(
        id: 999,
        name: 'Не существует',
        lat: 0,
        lng: 0,
        colorHex: '#000000',
        media: [media],
      );

      final count = await repository.update(orphan);

      expect(count, 0);
      expect(await mediaStore.exists(media.fileRef), isTrue);
    });
  });

  group('устойчивость хранилища', () {
    test('повреждённые записи пропускаются, целые — читаются', () async {
      await repository.create(markerWith(name: 'Целая', minute: 5));
      final decoded =
          jsonDecode(await storeFile.readAsString()) as List<dynamic>;
      decoded.addAll(<dynamic>['мусор', 42, null]);
      await storeFile.writeAsString(jsonEncode(decoded), flush: true);

      final all = await repository.getAll();
      expect(all.length, 1);
      expect(all.single.name, 'Целая');
    });

    test('повреждённое вложение не скрывает метку', () async {
      final good = MarkerMedia(
        fileRef: 'marker_media/1_ab.jpg',
        type: MarkerMedia.typePhoto,
        name: 'a.jpg',
        mimeType: 'image/jpeg',
        createdAt: DateTime(2026, 4, 1),
      );
      final stored = markerWith(name: 'С битым вложением').toMap()
        ..['media_json'] = jsonEncode(<dynamic>[
          good.toMap(),
          <String, dynamic>{'file_ref': '', 'type': 'photo'},
          <String, dynamic>{'type': 'voice'},
        ]);
      await storeFile.writeAsString(jsonEncode(<dynamic>[stored]), flush: true);

      final all = await repository.getAll();
      expect(all.length, 1);
      expect(all.single.media.length, 1);
      expect(all.single.media.single.fileRef, 'marker_media/1_ab.jpg');
    });

    test('восстанавливается из .bak, если основной файл пропал', () async {
      await repository.create(markerWith(name: 'Из бэкапа'));
      final contents = await storeFile.readAsString();
      await storeFile.writeAsString(contents, flush: true);
      await storeFile.copy('${storeFile.path}.bak');
      await storeFile.delete();

      final all = await repository.getAll();
      expect(all.single.name, 'Из бэкапа');
    });
  });
}
