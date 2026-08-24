import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../models/user_marker.dart';

class GpxExporter {
  /// Генерация GPX XML строки для трека
  static String buildTrackXml(Track track) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
        '<gpx version="1.1" creator="DiggerMaps" xmlns="http://www.topografix.com/GPX/1/1">');

    sb.writeln('  <metadata>');
    sb.writeln('    <name>${_escape(track.name)}</name>');
    sb.writeln('    <time>${track.createdAt.toIso8601String()}</time>');
    sb.writeln('  </metadata>');

    sb.writeln('  <trk>');
    sb.writeln('    <name>${_escape(track.name)}</name>');
    sb.writeln('    <trkseg>');
    for (final p in track.points) {
      sb.writeln('      <trkpt lat="${p.latitude}" lon="${p.longitude}" />');
    }
    sb.writeln('    </trkseg>');
    sb.writeln('  </trk>');

    sb.writeln('</gpx>');
    return sb.toString();
  }

  /// Сохраняет GPX в Downloads на Android или в каталог документов приложения.
  static Future<String> exportTrack(Track track) async {
    final Directory directory;
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      directory = await downloads.exists()
          ? downloads
          : await getApplicationDocumentsDirectory();
    } else {
      directory = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }

    final safeName = track.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName =
        '${safeName.isEmpty ? 'track' : safeName}_${track.createdAt.millisecondsSinceEpoch}.gpx';
    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(buildTrackXml(track), flush: true);
    return file.path;
  }

  /// Сохраняет GPX с пользовательскими метками в Downloads или документы.
  static Future<String> exportMarkers(List<UserMarker> markers) async {
    final Directory directory;
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      directory = await downloads.exists()
          ? downloads
          : await getApplicationDocumentsDirectory();
    } else {
      directory = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    final file = File(p.join(
      directory.path,
      'diggermaps_markers_${DateTime.now().millisecondsSinceEpoch}.gpx',
    ));
    await file.writeAsString(buildMarkersXml(markers), flush: true);
    return file.path;
  }

  /// Генерация GPX XML строки для списка меток.
  static String buildMarkersXml(List<UserMarker> markers) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
        '<gpx version="1.1" creator="DiggerMaps" xmlns="http://www.topografix.com/GPX/1/1">');

    for (final marker in markers) {
      sb.writeln('  <wpt lat="${marker.lat}" lon="${marker.lng}">');
      sb.writeln('    <name>${_escape(marker.name)}</name>');
      if (marker.description != null && marker.description!.isNotEmpty) {
        sb.writeln('    <desc>${_escape(marker.description!)}</desc>');
      }
      sb.writeln('    <time>${marker.createdAt.toIso8601String()}</time>');
      sb.writeln('  </wpt>');
    }

    sb.writeln('</gpx>');
    return sb.toString();
  }

  static String _escape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
