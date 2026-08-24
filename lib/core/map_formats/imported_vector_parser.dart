import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

class ImportedVectorGeometry {
  const ImportedVectorGeometry(this.points, {this.polygon = false});
  final List<LatLng> points;
  final bool polygon;
}

class ImportedVectorParser {
  static Future<List<ImportedVectorGeometry>> parse(String path) async {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'gpx' || ext == 'kml') {
      return _parseXml(await File(path).readAsString());
    }
    if (ext == 'kmz') {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final entry = archive.files.firstWhere(
        (file) => file.name.toLowerCase().endsWith('.kml'),
        orElse: () => throw const FormatException('В KMZ не найден KML'),
      );
      return _parseXml(utf8.decode(entry.content as List<int>));
    }
    return const [];
  }

  static List<ImportedVectorGeometry> _parseXml(String source) {
    final doc = XmlDocument.parse(source);
    final result = <ImportedVectorGeometry>[];
    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'coordinates') continue;
      final coords = node.innerText
          .trim()
          .split(RegExp(r'\s+'))
          .map((value) => value.split(','))
          .where((value) => value.length >= 2)
          .map((value) => LatLng(
                double.tryParse(value[1]) ?? 0,
                double.tryParse(value[0]) ?? 0,
              ))
          .where((point) => point.latitude != 0 || point.longitude != 0)
          .toList();
      if (coords.length >= 2) {
        result.add(ImportedVectorGeometry(coords,
            polygon: node.parent is XmlElement &&
                (node.parent! as XmlElement).name.local == 'Polygon'));
      }
    }
    for (final track in doc.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'trkseg' || node.name.local == 'rte')) {
      final points = track.descendants
          .whereType<XmlElement>()
          .where((node) =>
              node.name.local == 'trkpt' || node.name.local == 'rtept')
          .map((node) => LatLng(
                double.tryParse(node.getAttribute('lat') ?? '') ?? 0,
                double.tryParse(node.getAttribute('lon') ?? '') ?? 0,
              ))
          .where((point) => point.latitude != 0 || point.longitude != 0)
          .toList();
      if (points.length >= 2) result.add(ImportedVectorGeometry(points));
    }
    return result;
  }
}
