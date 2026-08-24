import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Легковесный файловый LRU-кэш сетевых тайлов.
///
/// Файл называется SHA-256 от полного URL, поэтому разные источники, стили и
/// параметры Sentinel не пересекаются. Время изменения используется как время
/// последнего доступа для очистки самых старых тайлов.
class TileCacheStore {
  TileCacheStore({
    this.maxSizeBytes = 256 * 1024 * 1024,
    this.maxAge = const Duration(days: 30),
    this.cleanupInterval = const Duration(minutes: 10),
  });

  final int maxSizeBytes;
  final Duration maxAge;
  final Duration cleanupInterval;

  Directory? _directory;
  Future<Directory>? _directoryFuture;
  DateTime? _lastCleanup;
  Future<void>? _cleanupFuture;

  Future<Uint8List?> read(String url) async {
    try {
      final file = await _fileFor(url);
      if (!await file.exists()) return null;

      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > maxAge) {
        await _deleteQuietly(file);
        return null;
      }

      final bytes = await file.readAsBytes();
      // Обновляем LRU-метку. Ошибка touch не должна ломать показ тайла.
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        // Кэш остаётся пригодным для чтения.
      }
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String url, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSizeBytes) return;

    try {
      final file = await _fileFor(url);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      _scheduleCleanup();
    } on FileSystemException {
      // Кэш является best-effort: сетевой тайл уже получен и должен отобразиться.
    }
  }

  Future<void> clear() async {
    try {
      final directory = await _getDirectory();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await directory.create(recursive: true);
    } on FileSystemException {
      // Очистка кэша не должна влиять на работу карты.
    }
  }

  Future<File> _fileFor(String url) async {
    final directory = await _getDirectory();
    final name = sha256.convert(url.codeUnits).toString();
    return File(p.join(directory.path, '$name.tile'));
  }

  Future<Directory> _getDirectory() {
    final existing = _directory;
    if (existing != null) return Future.value(existing);

    return _directoryFuture ??= () async {
      final root = await getApplicationCacheDirectory();
      final directory = Directory(p.join(root.path, 'network_tiles'));
      await directory.create(recursive: true);
      _directory = directory;
      return directory;
    }();
  }

  void _scheduleCleanup() {
    final now = DateTime.now();
    if (_lastCleanup != null &&
        now.difference(_lastCleanup!) < cleanupInterval) {
      return;
    }
    _lastCleanup = now;
    _cleanupFuture ??= _cleanup().whenComplete(() => _cleanupFuture = null);
  }

  Future<void> _cleanup() async {
    try {
      final directory = await _getDirectory();
      final files = <_CacheFile>[];
      var totalSize = 0;
      final cutoff = DateTime.now().subtract(maxAge);

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.tile')) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await _deleteQuietly(entity);
          continue;
        }
        files.add(_CacheFile(entity, stat.modified, stat.size));
        totalSize += stat.size;
      }

      if (totalSize <= maxSizeBytes) return;
      files.sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
      for (final cached in files) {
        await _deleteQuietly(cached.file);
        totalSize -= cached.size;
        if (totalSize <= maxSizeBytes) break;
      }
    } on FileSystemException {
      // Следующая плановая очистка попробует снова.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Игнорируем гонки чтения/очистки.
    }
  }
}

class _CacheFile {
  const _CacheFile(this.file, this.lastAccess, this.size);

  final File file;
  final DateTime lastAccess;
  final int size;
}
