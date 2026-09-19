import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/marker_media.dart';
import 'marker_media_store.dart';

/// Recording formats are chosen at runtime: `record` supports WAV on both
/// Android and Windows, and AAC/M4A is used as a fallback when a device refuses
/// the uncompressed encoder.
typedef _VoiceFormat = ({
  AudioEncoder encoder,
  String extension,
  String mimeType
});

/// The single place that knows how to obtain marker attachments.
///
/// Native resources (recorder/player) are created lazily so that metadata-only
/// use (sharing, exporting, listing) never initialises a platform plugin.
class MarkerMediaService {
  MarkerMediaService({MarkerMediaStore? store})
      : store = store ?? MarkerMediaStore();

  final MarkerMediaStore store;

  AudioRecorder? _recorder;
  AudioPlayer? _player;
  Stream<void>? _playbackComplete;
  String? _recordingRef;
  bool _disposed = false;
  final Stopwatch _clock = Stopwatch();

  /// Android and Windows only, matching the supported plugin set of the app.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Windows has no in-app camera: the gallery picker remains available.
  bool get cameraSupported =>
      supported && defaultTargetPlatform == TargetPlatform.android;

  bool get isRecording => _recordingRef != null;

  bool get isPlaying => _player?.state == PlayerState.playing;

  Stream<void> get playbackComplete =>
      _playbackComplete ??= (_player ??= AudioPlayer()).onPlayerComplete;

  /// Gallery (Windows/Android). Returns `null` when the user cancels.
  Future<MarkerMedia?> pickPhoto({bool camera = false}) async {
    if (!supported) {
      throw UnsupportedError('Медиа доступны на Android и Windows');
    }
    if (camera && !cameraSupported) {
      throw UnsupportedError('Камера недоступна на этом устройстве');
    }
    final String? path;
    if (camera) {
      path = (await ImagePicker().pickImage(source: ImageSource.camera))?.path;
    } else {
      // file_picker 11 exposes the static API; `FilePicker.platform` is gone.
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Выберите фотографию',
        type: FileType.custom,
        allowedExtensions: MarkerMediaStore.photoExtensions,
      );
      path = result?.files.single.path;
      if (result != null && path == null) {
        throw StateError('Не удалось открыть выбранный файл');
      }
    }
    return path == null ? null : importPhoto(path);
  }

  /// Copies an already known path into the managed folder. Also used by tests
  /// and by import flows that receive an explicit file path.
  Future<MarkerMedia> importPhoto(String sourcePath) =>
      store.importPhoto(sourcePath);

  Future<MarkerMedia?> pickVideo({bool camera = false}) async {
    if (!supported) {
      throw UnsupportedError('Медиа доступны на Android и Windows');
    }
    if (camera && !cameraSupported) {
      throw UnsupportedError('Камера недоступна на этом устройстве');
    }
    final String? path;
    if (camera) {
      path = (await ImagePicker().pickVideo(source: ImageSource.camera))?.path;
    } else {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Выберите видео',
        type: FileType.custom,
        allowedExtensions: MarkerMediaStore.videoExtensions,
      );
      path = result?.files.single.path;
      if (result != null && path == null) {
        throw StateError('Не удалось открыть выбранное видео');
      }
    }
    return path == null ? null : store.importVideo(path);
  }

  Future<void> openVideo(MarkerMedia media) async {
    final file = await store.resolve(media.fileRef);
    if (!media.isVideo || file == null || !await file.exists()) {
      throw StateError('Видео недоступно');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Private app files need a temporary content URI grant on Android.
      await const MethodChannel('digger_maps/media').invokeMethod<void>(
        'openVideo',
        <String, String>{'path': file.path, 'mimeType': media.mimeType},
      );
    } else if (!await launchUrl(file.uri,
        mode: LaunchMode.externalApplication)) {
      throw StateError('Не найдено приложение для просмотра видео');
    }
  }

  Future<void> startRecording() async {
    if (!supported) throw UnsupportedError('Запись недоступна на устройстве');
    if (isRecording) throw StateError('Запись уже идёт');
    final format = await _preferredVoiceFormat();
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('Разрешите доступ к микрофону в настройках');
    }
    final ref = await store.allocate(format.extension);
    final target = await store.resolve(ref);
    if (target == null) throw StateError('Не удалось подготовить файл записи');
    _recordingRef = ref;
    try {
      await recorder.start(
        RecordConfig(
          encoder: format.encoder,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: target.path,
      );
      _clock
        ..reset()
        ..start();
    } catch (_) {
      // The reserved file must not survive a failed start.
      await cancelRecording();
      rethrow;
    }
  }

  /// Stops the active recording and returns the persisted metadata.
  Future<MarkerMedia> stopRecording() async {
    final ref = _recordingRef;
    if (ref == null) throw StateError('Запись не начата');
    final recorder = _recorder;
    try {
      final path = await recorder?.stop();
      _clock.stop();
      final file = await store.resolve(ref);
      if (recorder == null ||
          path == null ||
          file == null ||
          !await file.exists() ||
          await file.length() <= 44) {
        throw StateError('Запись пуста. Проверьте микрофон');
      }
      _recordingRef = null;
      return MarkerMedia(
        fileRef: ref,
        type: MarkerMedia.typeVoice,
        name: 'Голосовая заметка.${_extensionOf(ref)}',
        mimeType: _mimeOf(ref),
        createdAt: DateTime.now(),
        bytes: await file.length(),
        durationMs: _clock.elapsedMilliseconds,
      );
    } catch (_) {
      await cancelRecording();
      rethrow;
    }
  }

  /// Aborts the active recording and deletes its partial file.
  Future<void> cancelRecording() async {
    final ref = _recordingRef;
    _recordingRef = null;
    _clock.stop();
    try {
      await _recorder?.cancel();
    } catch (_) {
      // The recorder may already be detached (e.g. app was killed).
    } finally {
      if (ref != null) await store.delete(ref);
    }
  }

  Future<void> play(MarkerMedia media) async {
    if (_disposed) throw StateError('Проигрыватель недоступен');
    final file = await store.resolve(media.fileRef);
    if (file == null || !await file.exists()) {
      throw StateError('Файл недоступен: сохранена только ссылка');
    }
    await (_player ??= AudioPlayer()).play(DeviceFileSource(file.path));
  }

  Future<void> stopPlayback() async {
    try {
      await _player?.stop();
    } catch (_) {
      // Stopping an idle player is not an error.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (isRecording) await cancelRecording();
    } finally {
      try {
        await _recorder?.dispose();
      } catch (_) {
        // Plugin already torn down with the engine.
      } finally {
        _recorder = null;
        try {
          await _player?.dispose();
        } catch (_) {
          // Ignore: dispose must never throw from a widget dispose.
        } finally {
          _player = null;
          _playbackComplete = null;
        }
      }
    }
  }

  /// User-facing message for any error thrown by this service.
  static String describeError(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    if (error is UnsupportedError) {
      return error.message ?? 'Операция недоступна на устройстве';
    }
    if (error is MissingPluginException) {
      return 'Медиа недоступны на этом устройстве';
    }
    if (error is PlatformException) {
      return 'Нет доступа к камере или файлам. Проверьте разрешения';
    }
    return 'Не удалось выполнить операцию с медиа';
  }

  Future<_VoiceFormat> _preferredVoiceFormat() async {
    const candidates = <_VoiceFormat>[
      (
        encoder: AudioEncoder.wav,
        extension: 'wav',
        mimeType: 'audio/wav',
      ),
      (
        encoder: AudioEncoder.aacLc,
        extension: 'm4a',
        mimeType: 'audio/mp4',
      ),
    ];
    final recorder = _recorder ??= AudioRecorder();
    for (final candidate in candidates) {
      try {
        if (await recorder.isEncoderSupported(candidate.encoder)) {
          return candidate;
        }
      } catch (_) {
        // Probe failed — try the next candidate.
      }
    }
    throw UnsupportedError('Запись звука недоступна на этом устройстве');
  }

  static String _extensionOf(String ref) {
    final index = ref.lastIndexOf('.');
    return index < 0 ? 'wav' : ref.substring(index + 1);
  }

  static String _mimeOf(String ref) =>
      _extensionOf(ref) == 'm4a' ? 'audio/mp4' : 'audio/wav';
}
