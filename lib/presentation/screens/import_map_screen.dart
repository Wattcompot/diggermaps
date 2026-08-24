// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xml/xml.dart';

import '../../data/models/track.dart';
import '../../data/repositories/imported_map_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/utils/measurement_utils.dart';
import '../../utils/ozi_map_parser.dart';

// =============================================================================
// Supported extensions
// =============================================================================
const _supportedExtensions = <String>{
  '.map',
  '.mbtiles',
  '.tif',
  '.tiff',
  '.gpx',
  '.kmz',
  '.kml',
  '.png',
  '.jpg',
  '.jpeg',
  '.ozf',
  '.ozf2',
  '.ozfx3',
  '.jnx',
  '.img',
  '.birdseye',
};

const _rasterExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.tif',
  '.tiff',
};

const _ozfExtensions = <String>{
  '.ozf',
  '.ozf2',
  '.ozfx3',
};

/// Full-screen file browser + importer for supported map/track formats.
///
/// The caller provides [currentMapCenter] so that raster-only images can be
/// placed with a reasonable fallback bounding box and [onImported] so that the
/// host knows when to refresh its layer list.
class ImportMapScreen extends StatefulWidget {
  const ImportMapScreen({
    required this.currentMapCenter,
    this.onImported,
    super.key,
  });

  /// Current map center used as a fallback for raster-only images.
  final LatLng currentMapCenter;

  /// Called after a successful import.
  final Future<void> Function()? onImported;

  @override
  State<ImportMapScreen> createState() => _ImportMapScreenState();
}

class _ImportMapScreenState extends State<ImportMapScreen> {
  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  String _currentPath = '';
  List<FileSystemEntity> _items = const [];
  bool _loading = false;
  bool _permissionGranted = false;
  bool _permissionDenied = false;
  String _statusText = '';
  String? _actionFeedback;

  final ImportedMapRepository _importedRepo = ImportedMapRepository();
  final TrackRepository _trackRepo = TrackRepository();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _statusText = 'Проверка разрешений…';
    });

    await _requestPermission();
    if (!_permissionGranted) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final startPath = await _resolveStartPath();
    if (!mounted) return;
    setState(() => _currentPath = startPath);
    await _navigateTo(startPath);
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid) {
      setState(() {
        _permissionGranted = true;
        _permissionDenied = false;
      });
      return;
    }

    late final Permission permission;
    if (await _isAndroid11OrAbove()) {
      permission = Permission.manageExternalStorage;
    } else {
      permission = Permission.storage;
    }

    final status = await permission.request();
    if (!mounted) return;

    if (status.isGranted || status == PermissionStatus.limited) {
      setState(() {
        _permissionGranted = true;
        _permissionDenied = false;
      });
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionGranted = false;
        _permissionDenied = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Доступ к файлам отклонён навсегда. '
                'Откройте настройки приложения и предоставьте разрешение.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
      }
    } else {
      setState(() {
        _permissionGranted = false;
        _permissionDenied = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Доступ к файлам отклонён.'),
              duration: Duration(seconds: 3),
            ),
          );
      }
    }
  }

  Future<bool> _isAndroid11OrAbove() async {
    if (!Platform.isAndroid) return false;
    try {
      // A simple heuristic: Android 11 = API 30
      final raw = await Process.run(
        'getprop',
        ['ro.build.version.sdk'],
        runInShell: true,
      );
      final sdk = int.tryParse(raw.stdout.toString().trim());
      return sdk != null && sdk >= 30;
    } catch (_) {
      return true; // assume recent Android
    }
  }

  // ---------------------------------------------------------------------------
  // Start path
  // ---------------------------------------------------------------------------

  Future<String> _resolveStartPath() async {
    if (Platform.isAndroid) {
      // /storage/emulated/0/Download
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) return downloadDir.path;

      // Fallback: /storage/emulated/0
      final rootDir = Directory('/storage/emulated/0');
      if (await rootDir.exists()) return rootDir.path;

      return '/storage/emulated/0';
    }

    // Desktop: application documents directory
    try {
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    } catch (_) {
      return Platform.isWindows ? r'C:\' : '/';
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _navigateTo(String path) async {
    setState(() {
      _loading = true;
      _currentPath = path;
      _statusText = '';
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final raw = await dir.list().toList();
      if (!mounted) return;

      // Sort: directories first (alphabetical), then files (alphabetical)
      raw.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir && !bDir) return -1;
        if (!aDir && bDir) return 1;
        return a.path.compareTo(b.path);
      });

      setState(() {
        _items = raw;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = 'Нет доступа к этой папке';
        });
      }
    }
  }

  void _goUp() {
    if (_currentPath == '/') return;
    final parent = p.dirname(_currentPath);
    if (parent == _currentPath) return;
    _navigateTo(parent);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isSupported(String path) {
    final lower = path.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  String _fileExtension(String path) {
    return p.extension(path).toLowerCase();
  }

  String _formatLabel(String path) {
    return switch (_fileExtension(path)) {
      '.map' => 'OziExplorer (.map)',
      '.mbtiles' => 'MBTiles',
      '.tif' || '.tiff' => 'GeoTIFF',
      '.gpx' => 'GPX трек',
      '.kmz' => 'KMZ',
      '.kml' => 'KML',
      '.png' || '.jpg' || '.jpeg' => 'Растр (без калибровки)',
      '.ozf' || '.ozf2' || '.ozfx3' => 'OZF2/OZFX3',
      '.jnx' => 'JNX (Birdseye)',
      '.img' => 'Garmin IMG',
      '.birdseye' => 'Birdseye',
      _ => path,
    };
  }

  // ---------------------------------------------------------------------------
  // Import triggering
  // ---------------------------------------------------------------------------

  Future<void> _onSupportedFileTap(String filePath) async {
    if (!mounted) return;
    final ext = _fileExtension(filePath);
    final basename = p.basename(filePath);

    // Show bottom sheet with name/format/import button
    final customName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ImportBottomSheet(
        filePath: filePath,
        fileName: basename,
        format: _formatLabel(filePath),
      ),
    );

    if (!mounted || customName == null) return;

    setState(() {
      _loading = true;
      _statusText = 'Импорт…';
    });

    try {
      _actionFeedback = null;
      await _importFile(filePath, ext, customName);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_actionFeedback ?? 'Импортировано: $customName'),
            duration: const Duration(seconds: 4),
          ),
        );
      await widget.onImported?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Ошибка импорта: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = '';
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Import dispatch
  // ---------------------------------------------------------------------------

  Future<void> _importFile(
    String filePath,
    String ext,
    String name,
  ) async {
    switch (ext) {
      case '.map':
        return _importOziMap(filePath, name);
      case '.ozf':
      case '.ozf2':
      case '.ozfx3':
        return _importOzfDirect(filePath, name);
      case '.png':
      case '.jpg':
      case '.jpeg':
        return _importRasterOnly(filePath, name);
      case '.tif':
      case '.tiff':
        return _importRasterOnly(filePath, name, isGeotiff: true);
      case '.mbtiles':
        return _importMbtiles(filePath, name);
      case '.gpx':
        return _importGpx(filePath, name);
      case '.kml':
        return _importKmlStub(name);
      case '.kmz':
        return _importKmzStub(name);
      case '.jnx':
        return _importJnx(filePath, name);
      case '.img':
        return _importGarminImgStub(name);
      case '.birdseye':
        return _importBirdseyeStub(name);
      default:
        throw Exception('Неподдерживаемый формат: $ext');
    }
  }

  // ---------------------------------------------------------------------------
  // Target directory for copies
  // ---------------------------------------------------------------------------

  Future<Directory> _createImportTargetDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final target = Directory(
      p.join(supportDir.path, 'imported_maps', '$ts'),
    );
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  // ---------------------------------------------------------------------------
  // .map import (Ozi)
  // ---------------------------------------------------------------------------

  Future<void> _importOziMap(String mapFilePath, String name) async {
    // 1. Parse the .map file
    final result = await OziMapParser.parseFile(mapFilePath);

    // 2. Validate calibration points
    if (result.points.isEmpty) {
      throw Exception(
        'Файл .map не содержит калибровочных точек. '
        'Проверьте файл в OziExplorer.',
      );
    }

    // 3. Build bounds
    final bounds = result.boundsJson;
    if (bounds == null) {
      throw Exception(
        'Не удалось вычислить границы карты по калибровочным точкам.',
      );
    }

    // OZF is read directly as a tile pyramid. No full-file conversion is
    // needed; only the source and its calibration are copied.
    final rawRasterPath = result.rasterPath;
    if (rawRasterPath != null &&
        _ozfExtensions.contains(p.extension(rawRasterPath).toLowerCase())) {
      final absOzfPath = _resolvePath(mapFilePath, rawRasterPath);
      if (await File(absOzfPath).exists()) {
        return _importOzfWithCalibration(
          ozfPath: absOzfPath,
          mapPath: mapFilePath,
          name: name,
          calibration: result,
        );
      }
    }

    final String? rasterPath = await _resolveRasterPath(
      mapFilePath: mapFilePath,
      rawRasterPath: rawRasterPath,
    );

    if (rasterPath == null) {
      throw Exception(
        'Не найден файл изображения, указанный в .map. '
        'Для OZF положите .map и .ozf/.ozfx3 рядом.',
      );
    }

    final absRasterPath = _resolvePath(mapFilePath, rasterPath);

    // 5. Copy files to app storage
    final targetDir = await _createImportTargetDir();
    final copiedMapPath = p.join(targetDir.path, p.basename(mapFilePath));
    final copiedRasterPath = p.join(targetDir.path, p.basename(absRasterPath));

    await File(mapFilePath).copy(copiedMapPath);
    await File(absRasterPath).copy(copiedRasterPath);

    // 6. Save to repository
    await _importedRepo.save(
      name: name,
      mapFilePath: copiedMapPath,
      imageFilePath: copiedRasterPath,
      format: 'ozi_map',
      boundsJson: bounds,
      calibrationPointsJson: result.calibrationPointsJson,
      offsetX: 0,
      offsetY: 0,
      opacity: 0.7,
      visible: true,
    );
  }

  /// Resolve the raster path from OziParseResult.
  ///
  /// 1. If rasterPath is present and points to a non-ozf image file → use it.
  /// 2. If rasterPath points to .ozf/.ozf2/.ozfx3 or is missing →
  ///    search for a raster with the same basename as the .map file,
  ///    then fall back to the basename of the specified raster.
  Future<String?> _resolveRasterPath({
    required String mapFilePath,
    required String? rawRasterPath,
  }) async {
    final mapDir = p.dirname(mapFilePath);
    final mapBasename = p.basenameWithoutExtension(mapFilePath);

    // Helper: check if a file exists and is a raster image
    Future<bool> isRasterFile(String path) async {
      if (!await File(path).exists()) return false;
      final lower = path.toLowerCase();
      return _rasterExtensions.any((ext) => lower.endsWith(ext));
    }

    // Case 1: explicit raster path that is not .ozf*
    if (rawRasterPath != null && rawRasterPath.isNotEmpty) {
      final lower = rawRasterPath.toLowerCase();
      final isOzf = _ozfExtensions.any((ext) => lower.endsWith(ext));

      if (!isOzf) {
        final abs = _resolvePath(mapFilePath, rawRasterPath);
        if (await isRasterFile(abs)) return abs;
      }
    }

    // Case 2: search by .map basename
    for (final ext in _rasterExtensions) {
      final candidate = p.join(mapDir, '$mapBasename$ext');
      if (await isRasterFile(candidate)) return candidate;
    }

    // Case 3: search by raster basename (if specified)
    if (rawRasterPath != null && rawRasterPath.isNotEmpty) {
      final rasterBasename = p.basenameWithoutExtension(rawRasterPath);
      if (rasterBasename != mapBasename) {
        for (final ext in _rasterExtensions) {
          final candidate = p.join(mapDir, '$rasterBasename$ext');
          if (await isRasterFile(candidate)) return candidate;
        }
      }
    }

    // Case 4: any raster in the same folder
    final dir = Directory(mapDir);
    if (await dir.exists()) {
      try {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            if (await isRasterFile(entity.path)) return entity.path;
          }
        }
      } catch (_) {
        // permission issue, ignore
      }
    }

    return null;
  }

  /// Resolves [candidate] relative to the directory of [mapFilePath] when it
  /// is a relative path; otherwise returns it unchanged.
  String _resolvePath(String mapFilePath, String candidate) {
    if (p.isAbsolute(candidate)) return candidate;
    return p.normalize(p.join(p.dirname(mapFilePath), candidate));
  }

  // ---------------------------------------------------------------------------
  // .ozf / .ozf2 / .ozfx3 direct selection
  // ---------------------------------------------------------------------------

  Future<void> _importOzfDirect(String ozfPath, String name) async {
    if (!Platform.isAndroid) {
      throw Exception('Нативное декодирование OZF поддерживается на Android.');
    }

    final mapPath = await _findMatchingMapFile(ozfPath);
    if (mapPath == null) {
      throw Exception('Для .ozf требуется файл калибровки .map');
    }

    final calibration = await OziMapParser.parseFile(mapPath);
    if (calibration.points.isEmpty || calibration.boundsJson == null) {
      throw Exception(
        'Файл .map не содержит корректных калибровочных точек.',
      );
    }

    return _importOzfWithCalibration(
      ozfPath: ozfPath,
      mapPath: mapPath,
      name: name,
      calibration: calibration,
    );
  }

  Future<void> _importOzfWithCalibration({
    required String ozfPath,
    required String mapPath,
    required String name,
    required OziMapParseResult calibration,
  }) async {
    final targetDir = await _createImportTargetDir();
    final copiedMapPath = p.join(targetDir.path, p.basename(mapPath));
    final copiedOzfPath = p.join(targetDir.path, p.basename(ozfPath));

    await File(mapPath).copy(copiedMapPath);
    await File(ozfPath).copy(copiedOzfPath);
    await _importedRepo.save(
      name: name,
      mapFilePath: copiedMapPath,
      imageFilePath: copiedOzfPath,
      format: p.extension(ozfPath).toLowerCase() == '.ozfx3' ? 'ozfx3' : 'ozf2',
      boundsJson: calibration.boundsJson,
      calibrationPointsJson: calibration.calibrationPointsJson,
      offsetX: 0,
      offsetY: 0,
      opacity: 0.7,
      visible: true,
    );
    _actionFeedback = 'OZF импортирован без конвертации: $name';
  }

  Future<String?> _findMatchingMapFile(String ozfPath) async {
    final directory = Directory(p.dirname(ozfPath));
    final expectedBase = p.basenameWithoutExtension(ozfPath).toLowerCase();
    if (!await directory.exists()) return null;

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            p.extension(entity.path).toLowerCase() != '.map') {
          continue;
        }
        if (p.basenameWithoutExtension(entity.path).toLowerCase() ==
            expectedBase) {
          return entity.path;
        }
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Raster-only (no .map calibration)
  // ---------------------------------------------------------------------------

  Future<void> _importRasterOnly(
    String filePath,
    String name, {
    bool isGeotiff = false,
  }) async {
    final targetDir = await _createImportTargetDir();
    final copiedPath = p.join(targetDir.path, p.basename(filePath));
    await File(filePath).copy(copiedPath);

    // Build a fallback bounding box around currentMapCenter ± 0.01°
    final c = widget.currentMapCenter;
    final boundsJson = jsonEncode({
      'minLat': c.latitude - 0.01,
      'maxLat': c.latitude + 0.01,
      'minLng': c.longitude - 0.01,
      'maxLng': c.longitude + 0.01,
    });

    await _importedRepo.save(
      name: name,
      imageFilePath: copiedPath,
      format: 'raster',
      boundsJson: boundsJson,
      offsetX: 0,
      offsetY: 0,
      opacity: 0.7,
      visible: true,
    );

    _actionFeedback =
        'Карта импортирована без калибровки. Используйте сдвиг для точного наложения.';
  }

  // ---------------------------------------------------------------------------
  // MBTiles
  // ---------------------------------------------------------------------------

  Future<void> _importMbtiles(String filePath, String name) async {
    final targetDir = await _createImportTargetDir();
    final copiedPath = p.join(targetDir.path, p.basename(filePath));
    await File(filePath).copy(copiedPath);

    await _importedRepo.save(
      name: name,
      imageFilePath: copiedPath,
      format: 'mbtiles',
      visible: true,
      offsetX: 0,
      offsetY: 0,
      opacity: 0.7,
    );
  }

  // ---------------------------------------------------------------------------
  // GPX
  // ---------------------------------------------------------------------------

  Future<void> _importGpx(String filePath, String name) async {
    final content = await File(filePath).readAsString();
    final doc = XmlDocument.parse(content);

    final points = <LatLng>[];

    // trkpt elements
    for (final trkpt in doc.findAllElements('trkpt')) {
      final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
      final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
      if (lat != null && lon != null) {
        points.add(LatLng(lat, lon));
      }
    }

    // rtept elements
    for (final rtept in doc.findAllElements('rtept')) {
      final lat = double.tryParse(rtept.getAttribute('lat') ?? '');
      final lon = double.tryParse(rtept.getAttribute('lon') ?? '');
      if (lat != null && lon != null) {
        points.add(LatLng(lat, lon));
      }
    }

    if (points.isEmpty) {
      throw Exception('GPX файл не содержит точек трека (trkpt / rtept).');
    }

    // Calculate total distance
    final distance = MeasurementUtils.totalDistance(points);

    // Save as Track
    final track = Track(
      name: name,
      points: points,
      distance: distance,
      duration: 0,
      visible: true,
    );

    await _trackRepo.create(track);

    // Keep a copied source for the imported-map list without depending on
    // external-storage permissions after the import.
    final targetDir = await _createImportTargetDir();
    final copiedPath = p.join(targetDir.path, p.basename(filePath));
    await File(filePath).copy(copiedPath);
    await _importedRepo.save(
      name: name,
      imageFilePath: copiedPath,
      format: 'gpx_track',
      visible: true,
      offsetX: 0,
      offsetY: 0,
      opacity: 0.7,
    );
  }

  // ---------------------------------------------------------------------------
  // KML stub
  // ---------------------------------------------------------------------------

  Future<void> _importKmlStub(String name) async {
    throw Exception(
      'Формат в разработке. Конвертируйте в .gpx через GPSBabel.',
    );
  }

  // ---------------------------------------------------------------------------
  // KMZ stub
  // ---------------------------------------------------------------------------

  Future<void> _importKmzStub(String name) async {
    throw Exception(
      'Формат в разработке. Конвертируйте в .gpx через GPSBabel.',
    );
  }

  // ---------------------------------------------------------------------------
  // JNX
  // ---------------------------------------------------------------------------

  Future<void> _importJnx(String filePath, String name) async {
    // Read up to 64 header bytes
    final file = File(filePath);
    final raf = await file.open(mode: FileMode.read);
    String? headerInfo;
    try {
      final header = await raf.read(64);
      if (header.isNotEmpty) {
        // Try to detect the JNX signature (should start with "JNX" or
        // "BirdsEye")
        try {
          final str = utf8.decode(header, allowMalformed: true);
          headerInfo = str.trim().isNotEmpty ? str : null;
        } catch (_) {
          headerInfo = 'Бинарный заголовок (${header.length} байт)';
        }
      }
    } finally {
      await raf.close();
    }

    final headerSuffix = headerInfo == null ? '' : ' Заголовок прочитан.';
    throw Exception(
      'JNX — бинарный формат Garmin. Конвертируйте в .mbtiles или .map + .png '
      'через Global Mapper / QMapShack.$headerSuffix',
    );
  }

  // ---------------------------------------------------------------------------
  // Garmin IMG stub
  // ---------------------------------------------------------------------------

  Future<void> _importGarminImgStub(String name) async {
    throw Exception(
      'Garmin .img — векторный формат. Конвертируйте в .gpx через GPSBabel '
      'или в .map + .png через GPSMapEdit.',
    );
  }

  // ---------------------------------------------------------------------------
  // Birdseye stub
  // ---------------------------------------------------------------------------

  Future<void> _importBirdseyeStub(String name) async {
    throw Exception(
      'BirdsEye — проприетарный формат Garmin. Используйте JNX-конвертер на ПК.',
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Импорт карты'),
        backgroundColor: const Color(0xFFA67B5B),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Permission denied state
    if (_permissionDenied && !_permissionGranted) {
      return _buildPermissionDenied();
    }

    // Loading / initial
    if (_loading && _items.isEmpty && _statusText.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFFA67B5B),
            ),
            const SizedBox(height: 16),
            Text(
              _statusText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildPathBar(),
        if (_loading) const LinearProgressIndicator(color: Color(0xFFA67B5B)),
        Expanded(child: _buildFileList()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Permission denied widget
  // ---------------------------------------------------------------------------

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_off_rounded,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              Platform.isAndroid
                  ? 'Для импорта карт необходим доступ к файлам устройства.\n\n'
                      'Откройте настройки приложения и предоставьте '
                      'разрешение «Файлы и медиа» или «Управление всеми '
                      'файлами».'
                  : 'Нет доступа к файловой системе.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                setState(() {
                  _permissionDenied = false;
                });
                await _requestPermission();
                if (!mounted) return;
                if (_permissionGranted) {
                  await _init();
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA67B5B),
                foregroundColor: Colors.white,
              ),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await openAppSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Настройки приложения'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Path bar
  // ---------------------------------------------------------------------------

  Widget _buildPathBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFF0EDE6),
      child: Row(
        children: [
          IconButton(
            onPressed: _goUp,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Назад',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              _currentPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (_statusText.isNotEmpty)
            Text(
              _statusText,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // File list
  // ---------------------------------------------------------------------------

  Widget _buildFileList() {
    if (_items.isEmpty && !_loading) {
      return Center(
        child: Text(
          'Папка пуста',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final entity = _items[index];
        final isDir = entity is Directory;
        final isSupported = !isDir && _isSupported(entity.path);

        return ListTile(
          leading: Icon(
            isDir ? Icons.folder : Icons.insert_drive_file,
            color: isDir
                ? const Color(0xFFA67B5B)
                : isSupported
                    ? const Color(0xFFA67B5B)
                    : Colors.grey,
          ),
          title: Text(
            p.basename(entity.path),
            style: TextStyle(
              color: isSupported
                  ? const Color(0xFFA67B5B)
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: isSupported ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: isSupported
              ? Text(
                  _formatLabel(entity.path),
                  style: TextStyle(
                    fontSize: 12,
                    color: isSupported
                        ? const Color(0xFF8B5E34)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
                )
              : null,
          onTap: () {
            if (isDir) {
              _navigateTo(entity.path);
            } else if (isSupported) {
              _onSupportedFileTap(entity.path);
            }
          },
        );
      },
    );
  }
}

// =============================================================================
// Bottom sheet for name entry
// =============================================================================
class _ImportBottomSheet extends StatefulWidget {
  const _ImportBottomSheet({
    required this.filePath,
    required this.fileName,
    required this.format,
  });

  final String filePath;
  final String fileName;
  final String format;

  @override
  State<_ImportBottomSheet> createState() => _ImportBottomSheetState();
}

class _ImportBottomSheetState extends State<_ImportBottomSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: p.basenameWithoutExtension(widget.fileName),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // File name
            Text(
              widget.fileName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            // Format
            Text(
              widget.format,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            // Name field
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: const InputDecoration(
                labelText: 'Название слоя',
                hintText: 'Введите имя',
              ),
            ),
            const SizedBox(height: 20),
            // Import button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final name = _controller.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Введите название'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    return;
                  }
                  Navigator.pop(context, name);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA67B5B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Импортировать',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
