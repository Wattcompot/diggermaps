import 'dart:io';

import 'package:digger_maps/presentation/screens/import_directory_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ImportArchiveFormats', () {
    test('распознаёт простые и составные архивы по пути', () {
      expect(ImportArchiveFormats.isArchive(r'C:\maps\ozi.zip'), isTrue);
      expect(ImportArchiveFormats.isArchive('/maps/backup.tar.gz'), isTrue);
      expect(ImportArchiveFormats.isArchive('/maps/backup.TAR.BZ2'), isTrue);
      expect(ImportArchiveFormats.isArchive('/maps/tiles.tar.xz'), isTrue);
      expect(ImportArchiveFormats.isArchive('/maps/photo.jpg'), isFalse);
      expect(ImportArchiveFormats.isArchive('/maps/note.txt'), isFalse);
    });
  });

  group('ImportDirectoryIndex', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('digger_picker_test');
      await File(p.join(dir.path, 'zeta.txt'))
          .writeAsBytes(List<int>.filled(10, 0));
      await File(p.join(dir.path, 'Alpha.zip'))
          .writeAsBytes(List<int>.filled(500, 0));
      await File(p.join(dir.path, 'middle.tar.gz'))
          .writeAsBytes(List<int>.filled(100, 0));
      await Directory(p.join(dir.path, 'subdir')).create();
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('load читает каталог и метаданные один раз за проход', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      expect(entries, hasLength(4));

      final zip = entries.firstWhere((entry) => entry.name == 'Alpha.zip');
      expect(zip.isDirectory, isFalse);
      expect(zip.isArchive, isTrue);
      expect(zip.sizeBytes, 500);
      expect(zip.modified, isNotNull);

      final compound =
          entries.firstWhere((entry) => entry.name == 'middle.tar.gz');
      expect(compound.isArchive, isTrue);

      final folder = entries.firstWhere((entry) => entry.name == 'subdir');
      expect(folder.isDirectory, isTrue);
      expect(folder.isArchive, isFalse);
    });

    test('поиск по имени без учёта регистра', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      final found = ImportDirectoryIndex.apply(entries: entries, query: 'ZIP');
      expect(found.map((entry) => entry.name), <String>['Alpha.zip']);

      final partial =
          ImportDirectoryIndex.apply(entries: entries, query: 'MID');
      expect(partial.map((entry) => entry.name), <String>['middle.tar.gz']);

      final nothing =
          ImportDirectoryIndex.apply(entries: entries, query: 'нет-такого');
      expect(nothing, isEmpty);
    });

    test('каталоги всегда первыми, сортировка по имени', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      final sorted = ImportDirectoryIndex.apply(entries: entries);

      expect(sorted.first.isDirectory, isTrue);
      expect(sorted.first.name, 'subdir');
      expect(
        sorted.skip(1).map((entry) => entry.nameLower),
        <String>['alpha.zip', 'middle.tar.gz', 'zeta.txt'],
      );
    });

    test('сортировка по размеру по убыванию', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      final sorted = ImportDirectoryIndex.apply(
        entries: entries,
        field: ImportSortField.size,
        ascending: false,
      );

      expect(sorted.first.isDirectory, isTrue);
      expect(
        sorted.skip(1).map((entry) => entry.sizeBytes),
        <int?>[500, 100, 10],
      );
    });

    test('сортировка по дате изменения на синтетических записях', () {
      final older = ImportDirectoryEntry(
        path: '/f/old.txt',
        isDirectory: false,
        isArchive: false,
        modified: DateTime(2020),
      );
      final newer = ImportDirectoryEntry(
        path: '/f/new.txt',
        isDirectory: false,
        isArchive: false,
        modified: DateTime(2024),
      );

      final descending = ImportDirectoryIndex.apply(
        entries: <ImportDirectoryEntry>[older, newer],
        field: ImportSortField.modified,
        ascending: false,
      );
      expect(descending.first.name, 'new.txt');

      final ascending = ImportDirectoryIndex.apply(
        entries: <ImportDirectoryEntry>[newer, older],
        field: ImportSortField.modified,
      );
      expect(ascending.first.name, 'old.txt');
    });

    test('archivesFirst поднимает архивы над остальными файлами', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      final sorted = ImportDirectoryIndex.apply(
        entries: entries,
        archivesFirst: true,
      );

      expect(sorted.first.isDirectory, isTrue);
      final files = sorted.skip(1).toList();
      expect(files.take(2).every((entry) => entry.isArchive), isTrue);
      expect(files.last.name, 'zeta.txt');
    });

    test('archivesFirst не меняет порядок каталогов', () async {
      final entries = await ImportDirectoryIndex.load(dir);
      final sorted = ImportDirectoryIndex.apply(
        entries: entries,
        archivesFirst: true,
        ascending: false,
      );
      expect(sorted.first.name, 'subdir');
      expect(sorted.first.isDirectory, isTrue);
    });
  });
}
