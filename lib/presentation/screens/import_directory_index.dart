import 'dart:io';

import 'package:path/path.dart' as p;

/// Поле сортировки встроенного файлового picker'а импорта.
enum ImportSortField { name, modified, size }

/// Распознавание архивов по пути.
///
/// Тип архива доступен только по имени файла (расширению) — содержимое не
/// читаем. Поддерживаются составные расширения `.tar.gz`, `.tar.bz2`,
/// `.tar.xz`, поэтому проверка идёт по списку суффиксов от длинных к коротким.
class ImportArchiveFormats {
  ImportArchiveFormats._();

  /// Суффиксы архивов; составные перечислены раньше коротких.
  static const List<String> suffixes = <String>[
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tgz',
    '.tbz2',
    '.txz',
    '.zip',
    '.tar',
    '.gz',
    '.bz2',
    '.xz',
    '.7z',
    '.rar',
  ];

  static bool isArchive(String path) {
    final lower = path.toLowerCase();
    return suffixes.any(lower.endsWith);
  }
}

/// Снимок одной записи каталога.
///
/// Метаданные (размер, дата) читаются один раз при загрузке каталога, поэтому
/// фильтрация и сортировка не выполняют ввод-вывод и не зависят от [BuildContext].
class ImportDirectoryEntry {
  ImportDirectoryEntry({
    required this.path,
    required this.isDirectory,
    required this.isArchive,
    this.sizeBytes,
    this.modified,
  })  : name = p.basename(path),
        nameLower = p.basename(path).toLowerCase();

  final String path;
  final String name;
  final String nameLower;
  final bool isDirectory;
  final bool isArchive;
  final int? sizeBytes;
  final DateTime? modified;

  /// Case-insensitive поиск по имени.
  bool matches(String lowerCaseQuery) => nameLower.contains(lowerCaseQuery);

  int compareTo(ImportDirectoryEntry other, ImportSortField field) {
    switch (field) {
      case ImportSortField.name:
        final byName = nameLower.compareTo(other.nameLower);
        return byName != 0 ? byName : path.compareTo(other.path);
      case ImportSortField.modified:
        final a = (modified ?? _epoch).millisecondsSinceEpoch;
        final b = (other.modified ?? _epoch).millisecondsSinceEpoch;
        final byDate = a.compareTo(b);
        return byDate != 0 ? byDate : nameLower.compareTo(other.nameLower);
      case ImportSortField.size:
        final bySize = (sizeBytes ?? 0).compareTo(other.sizeBytes ?? 0);
        return bySize != 0 ? bySize : nameLower.compareTo(other.nameLower);
    }
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Загрузка каталога и применение фильтра/сортировки.
///
/// [load] выполняет `Directory.list` и ровно один `stat` на запись за проход,
/// после чего все операции над списком синхронные.
class ImportDirectoryIndex {
  ImportDirectoryIndex._();

  static Future<List<ImportDirectoryEntry>> load(Directory directory) async {
    final entities = await directory.list().toList();
    return Future.wait(entities.map(_toEntry));
  }

  static Future<ImportDirectoryEntry> _toEntry(FileSystemEntity entity) async {
    final isDirectory = entity is Directory;
    int? size;
    DateTime? modified;
    try {
      final stat = await entity.stat();
      modified = stat.modified;
      if (!isDirectory) size = stat.size;
    } catch (_) {
      // Битые ссылки / недоступные записи остаются без метаданных.
    }
    return ImportDirectoryEntry(
      path: entity.path,
      isDirectory: isDirectory,
      isArchive: !isDirectory && ImportArchiveFormats.isArchive(entity.path),
      sizeBytes: size,
      modified: modified,
    );
  }

  /// Фильтрует записи по [query] (без учёта регистра) и сортирует их.
  ///
  /// Каталоги всегда идут первыми; при [archivesFirst] архивы поднимаются перед
  /// остальными файлами, но внутри каталогов порядок по полю не меняется.
  static List<ImportDirectoryEntry> apply({
    required List<ImportDirectoryEntry> entries,
    String query = '',
    ImportSortField field = ImportSortField.name,
    bool ascending = true,
    bool archivesFirst = false,
  }) {
    final normalized = query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? List<ImportDirectoryEntry>.of(entries)
        : entries.where((entry) => entry.matches(normalized)).toList();

    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      if (archivesFirst && a.isArchive != b.isArchive) {
        return a.isArchive ? -1 : 1;
      }
      final byField = a.compareTo(b, field);
      return ascending ? byField : -byField;
    });
    return filtered;
  }
}
