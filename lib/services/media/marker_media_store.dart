import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/marker_media.dart';

/// Files for marker attachments live in `<documents>/marker_media/<name>.<ext>`.
///
/// The database only ever stores that short relative reference, never a blob and
/// never an absolute path: a marker exported to JSON/GPX stays portable, and a
/// foreign reference (produced by an import, or by a future cloud sync) can
/// never be resolved into "somewhere on the user's disk". [delete] therefore
/// never touches the original file the user picked in the gallery.
class MarkerMediaStore {
  MarkerMediaStore({this.documentsDirectory});

  /// Injectable for tests; production code uses the application documents dir.
  final Directory? documentsDirectory;

  static const String directoryName = 'marker_media';
  static const String defaultMimeType = 'application/octet-stream';

  static const Map<String, String> photoMimeTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
  };

  /// Extensions offered by the gallery picker.
  static List<String> get photoExtensions => photoMimeTypes.keys.toList();

  static const Map<String, String> videoMimeTypes = <String, String>{
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    '3gp': 'video/3gpp',
  };

  /// Extensions offered by the video picker.
  static List<String> get videoExtensions => videoMimeTypes.keys.toList();

  static final RegExp _managedRef =
      RegExp(r'^marker_media/[A-Za-z0-9_-]+\.[a-z0-9]{1,5}$');
  static final RegExp _extension = RegExp(r'^[a-z0-9]{1,5}$');

  /// Only managed references are ever turned into a file path.
  static bool isManagedRef(String ref) => _managedRef.hasMatch(ref);

  /// Refs created during an editing session that must be deleted when the
  /// session is cancelled: everything present now, minus what the saved marker
  /// already owned. Persisted attachments are never part of the result.
  static Set<String> draftRefs({
    required Iterable<String> originalRefs,
    required Iterable<String> currentRefs,
  }) =>
      currentRefs.toSet().difference(originalRefs.toSet());

  Future<Directory> root() async =>
      documentsDirectory ?? await getApplicationDocumentsDirectory();

  Future<File?> resolve(String ref) async {
    if (!isManagedRef(ref)) return null;
    final segments = ref.split('/');
    final directory = await root();
    // `joinAll` keeps Windows separators correct and avoids passing a spread
    // argument list to `path.join`.
    return File(p.joinAll(<String>[directory.path, ...segments]));
  }

  Future<bool> exists(String ref) async {
    final file = await resolve(ref);
    return file != null && await file.exists();
  }

  /// Reserves a unique managed name. The caller writes the file itself
  /// (the recorder streams straight into the returned path).
  Future<String> allocate(String extension) async {
    final normalized = extension.replaceFirst('.', '').toLowerCase();
    if (!_extension.hasMatch(normalized)) {
      throw const FormatException('Недопустимое расширение файла');
    }
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final ref = '$directoryName/'
        '${DateTime.now().microsecondsSinceEpoch}_$suffix.$normalized';
    final file = await resolve(ref);
    if (file == null) throw const FormatException('Недопустимая ссылка медиа');
    await file.parent.create(recursive: true);
    return ref;
  }

  /// Copies a gallery/camera file into the managed folder and returns the
  /// metadata that is persisted with the marker. The original stays untouched.
  Future<MarkerMedia> importPhoto(String sourcePath) => _importFile(
        sourcePath,
        type: MarkerMedia.typePhoto,
        mimeTypes: photoMimeTypes,
        unsupportedMessage: 'Выберите JPG, PNG, WebP, GIF или BMP',
        emptyMessage: 'Файл фотографии пуст',
      );

  /// Same as [importPhoto] for a video clip (gallery or camera).
  Future<MarkerMedia> importVideo(String sourcePath, {int? durationMs}) =>
      _importFile(
        sourcePath,
        type: MarkerMedia.typeVideo,
        mimeTypes: videoMimeTypes,
        unsupportedMessage: 'Выберите MP4, MOV, WebM, MKV или 3GP',
        emptyMessage: 'Файл видео пуст',
        durationMs: durationMs,
      );

  Future<MarkerMedia> _importFile(
    String sourcePath, {
    required String type,
    required Map<String, String> mimeTypes,
    required String unsupportedMessage,
    required String emptyMessage,
    int? durationMs,
  }) async {
    final extension =
        p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final mimeType = mimeTypes[extension];
    if (mimeType == null) {
      throw FormatException(unsupportedMessage);
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FormatException('Файл не найден');
    }
    final ref = await allocate(extension);
    final target = await resolve(ref);
    if (target == null) {
      throw const FormatException('Недопустимая ссылка медиа');
    }
    try {
      await source.copy(target.path);
      final bytes = await target.length();
      if (bytes == 0) throw FormatException(emptyMessage);
      return MarkerMedia(
        fileRef: ref,
        type: type,
        name: p.basename(sourcePath),
        mimeType: mimeType,
        bytes: bytes,
        createdAt: DateTime.now(),
        durationMs: durationMs,
      );
    } catch (_) {
      // A half-copied draft must not survive a failed import.
      await delete(ref);
      rethrow;
    }
  }

  /// Idempotent: a missing file (already cleaned, or a foreign reference) is a
  /// no-op, so a retry can never throw at the caller.
  Future<void> delete(String ref) async {
    final file = await resolve(ref);
    if (file == null) return;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } on FileSystemException catch (error) {
        // Windows can briefly retain a handle after thumbnail decoding.
        if (!Platform.isWindows ||
            error.osError?.errorCode != 32 ||
            attempt == 4) {
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }
    }
  }

  Future<void> deleteAll(Iterable<String> refs) async {
    for (final ref in refs.toSet()) {
      await delete(ref);
    }
  }

  /// Removes files created during a cancelled editing session and reports how
  /// many were deleted. Never touches the attachments of the saved marker and
  /// never touches files outside the managed folder.
  Future<int> discardDrafts({
    required Iterable<String> originalRefs,
    required Iterable<String> currentRefs,
  }) async {
    final drafts = draftRefs(
      originalRefs: originalRefs,
      currentRefs: currentRefs,
    ).where(isManagedRef);
    var removed = 0;
    for (final ref in drafts) {
      if (await exists(ref)) {
        await delete(ref);
        removed++;
      }
    }
    return removed;
  }
}
