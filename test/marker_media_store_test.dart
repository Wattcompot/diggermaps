import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/services/media/marker_media_store.dart';

void main() {
  late Directory root;
  late MarkerMediaStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('digger_media_store');
    store = MarkerMediaStore(documentsDirectory: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File sourcePhoto(String name) {
    final file = File(p.join(root.path, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(120, 7));
    return file;
  }

  group('ссылки', () {
    test('принимаются только управляемые ссылки', () {
      expect(MarkerMediaStore.isManagedRef('marker_media/1_ab.jpg'), isTrue);
      expect(MarkerMediaStore.isManagedRef('marker_media/1_ab.wav'), isTrue);
      expect(MarkerMediaStore.isManagedRef('../secrets.txt'), isFalse);
      expect(
          MarkerMediaStore.isManagedRef('marker_media/../../x.jpg'), isFalse);
      expect(MarkerMediaStore.isManagedRef('/abs/path.jpg'), isFalse);
      expect(MarkerMediaStore.isManagedRef(r'C:\photo.jpg'), isFalse);
      expect(MarkerMediaStore.isManagedRef('other_dir/x.jpg'), isFalse);
    });

    test('чужие ссылки не превращаются в путь', () async {
      expect(await store.resolve('../../etc/passwd'), isNull);
      expect(await store.resolve('/tmp/photo.jpg'), isNull);
    });

    test('allocate создаёт папку и валидную ссылку', () async {
      final ref = await store.allocate('jpg');
      expect(MarkerMediaStore.isManagedRef(ref), isTrue);
      expect(ref.endsWith('.jpg'), isTrue);
      final file = await store.resolve(ref);
      expect(file, isNotNull);
      expect(file!.parent.existsSync(), isTrue);
      expect(await store.exists(ref), isFalse);
      expect(() => store.allocate('jpg/../exe'), throwsFormatException);
    });
  });

  group('импорт фото', () {
    test('копирует файл и не трогает оригинал', () async {
      final source = sourcePhoto('IMG_0001.JPG');
      final media = await store.importPhoto(source.path);

      expect(media.type, MarkerMedia.typePhoto);
      expect(media.mimeType, 'image/jpeg');
      expect(media.bytes, 120);
      expect(media.name, 'IMG_0001.JPG');
      expect(MarkerMediaStore.isManagedRef(media.fileRef), isTrue);

      final copy = await store.resolve(media.fileRef);
      expect(copy!.existsSync(), isTrue);
      expect(source.existsSync(), isTrue);
      expect(copy.path, isNot(source.path));
    });

    test('отклоняет неподдерживаемое расширение и отсутствующий файл',
        () async {
      final text = File(p.join(root.path, 'note.txt'))..writeAsStringSync('hi');
      await expectLater(store.importPhoto(text.path), throwsFormatException);
      await expectLater(
        store.importPhoto(p.join(root.path, 'missing.jpg')),
        throwsFormatException,
      );
      expect(
        Directory(p.join(root.path, MarkerMediaStore.directoryName))
            .existsSync(),
        isFalse,
      );
    });

    test('пустой файл не остаётся в хранилище', () async {
      final empty = File(p.join(root.path, 'empty.png'))..createSync();
      await expectLater(store.importPhoto(empty.path), throwsFormatException);
      final directory =
          Directory(p.join(root.path, MarkerMediaStore.directoryName));
      expect(directory.listSync().whereType<File>(), isEmpty);
    });
  });

  group('импорт видео', () {
    test('сохраняет видео, модель и оригинал независимо', () async {
      final source = sourcePhoto('clip.MP4');
      final media = await store.importVideo(source.path);
      expect(media.type, MarkerMedia.typeVideo);
      expect(media.mimeType, 'video/mp4');
      expect(media.isVideo, isTrue);
      expect(MarkerMedia.fromMap(media.toMap()).fileRef, media.fileRef);
      expect(await store.exists(media.fileRef), isTrue);
      await store.delete(media.fileRef);
      expect(source.existsSync(), isTrue);
    });

    test('отклоняет отсутствующее, пустое или неподдерживаемое видео',
        () async {
      await expectLater(store.importVideo(sourcePhoto('clip.txt').path),
          throwsFormatException);
      await expectLater(store.importVideo(p.join(root.path, 'missing.mp4')),
          throwsFormatException);
      final empty = File(p.join(root.path, 'empty.mp4'))..createSync();
      await expectLater(store.importVideo(empty.path), throwsFormatException);
    });
  });

  group('удаление', () {
    test('удаляет управляемый файл и идемпотентно', () async {
      final media = await store.importPhoto(sourcePhoto('a.jpg').path);
      final file = await store.resolve(media.fileRef);
      await store.delete(media.fileRef);
      expect(file!.existsSync(), isFalse);
      await store.delete(media.fileRef);
    });

    test('не удаляет файл по чужой ссылке', () async {
      final outside = sourcePhoto('outside.jpg');
      await store.delete(outside.path);
      await store.delete('photos/outside.jpg');
      expect(outside.existsSync(), isTrue);
    });

    test('deleteAll удаляет только управляемые ссылки', () async {
      final first = await store.importPhoto(sourcePhoto('a.jpg').path);
      final second = await store.importPhoto(sourcePhoto('b.png').path);
      final outside = sourcePhoto('c.jpg');
      await store.deleteAll(<String>[
        first.fileRef,
        second.fileRef,
        outside.path,
      ]);
      expect(await store.exists(first.fileRef), isFalse);
      expect(await store.exists(second.fileRef), isFalse);
      expect(outside.existsSync(), isTrue);
    });
  });

  group('черновики отменённой сессии', () {
    test('draftRefs = текущие минус сохранённые', () {
      final drafts = MarkerMediaStore.draftRefs(
        originalRefs: <String>['marker_media/1_ab.jpg'],
        currentRefs: <String>[
          'marker_media/1_ab.jpg',
          'marker_media/2_cd.wav',
          'photos/foreign.jpg',
        ],
      );
      expect(drafts, <String>{'marker_media/2_cd.wav', 'photos/foreign.jpg'});
    });

    test('отмена удаляет черновик и сохраняет вложение метки', () async {
      final saved = await store.importPhoto(sourcePhoto('saved.jpg').path);
      final draft = await store.importPhoto(sourcePhoto('draft.jpg').path);

      final removed = await store.discardDrafts(
        originalRefs: <String>{saved.fileRef},
        currentRefs: <String>{saved.fileRef, draft.fileRef},
      );

      expect(removed, 1);
      expect(await store.exists(draft.fileRef), isFalse);
      expect(await store.exists(saved.fileRef), isTrue);
    });

    test('отмена не трогает внешние ссылки и уже удалённые черновики',
        () async {
      final outside = sourcePhoto('keep.jpg');
      final removed = await store.discardDrafts(
        originalRefs: const <String>{},
        currentRefs: <String>[outside.path, 'marker_media/gone.jpg'],
      );
      expect(removed, 0);
      expect(outside.existsSync(), isTrue);
    });
  });
}
