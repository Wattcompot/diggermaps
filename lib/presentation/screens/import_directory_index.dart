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
    required this.isSupported,
    this.sizeBytes,
    this.modified,
  })  : name = p.basename(path),
        nameLower = p.basename(path).toLowerCase();

  final String path;
  final String name;
  final String nameLower;
  final bool isDirectory;
  final bool isArchive;

  /// Файл имеет одно из уже поддерживаемых картографических расширений
  /// (см. whitelist, переданный в [ImportDirectoryIndex.load]).
  final bool isSupported;
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

  static Future<List<ImportDirectoryEntry>> load(
    Directory directory, {
    Set<String> supportedExtensions = const <String>{},
  }) async {
    final entities = await directory.list().toList();
    return Future.wait(
      entities.map((entity) => _toEntry(entity, supportedExtensions)),
    );
  }

  static Future<ImportDirectoryEntry> _toEntry(
    FileSystemEntity entity,
    Set<String> supportedExtensions,
  ) async {
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
      isSupported: !isDirectory &&
          _hasSupportedExtension(entity.path, supportedExtensions),
      sizeBytes: size,
      modified: modified,
    );
  }

  static bool _hasSupportedExtension(
    String path,
    Set<String> supportedExtensions,
  ) {
    if (supportedExtensions.isEmpty) return false;
    final lower = path.toLowerCase();
    return supportedExtensions.any(lower.endsWith);
  }

  /// Фильтрует записи по [query] (без учёта регистра) и сортирует их.
  ///
  /// Каталоги всегда идут первыми. При [supportedFirst] уже поддерживаемые
  /// картографические файлы поднимаются сразу за каталогами (перед прочими
  /// файлами и архивами), при [archivesFirst] — архивы. Внутри каждой группы
  /// порядок задаёт выбранное поле, поэтому обычные файлы не исчезают, а лишь
  /// смещаются ниже.
  static List<ImportDirectoryEntry> apply({
    required List<ImportDirectoryEntry> entries,
    String query = '',
    ImportSortField field = ImportSortField.name,
    bool ascending = true,
    bool archivesFirst = false,
    bool supportedFirst = false,
  }) {
    final normalized = query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? List<ImportDirectoryEntry>.of(entries)
        : entries.where((entry) => entry.matches(normalized)).toList();

    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      if (supportedFirst && a.isSupported != b.isSupported) {
        return a.isSupported ? -1 : 1;
      }
      if (archivesFirst && a.isArchive != b.isArchive) {
        return a.isArchive ? -1 : 1;
      }
      final byField = a.compareTo(b, field);
      return ascending ? byField : -byField;
    });
    return filtered;
  }
}
