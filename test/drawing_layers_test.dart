import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/data/models/drawing.dart';
import 'package:digger_maps/data/utils/measurement_utils.dart';
import 'package:digger_maps/presentation/providers/drawing_controller.dart';
import 'package:digger_maps/presentation/widgets/poi/drawing_label_layer.dart';
import 'package:digger_maps/presentation/widgets/poi/paint_line_layer.dart';

void main() {
  const p1 = LatLng(55.000, 37.000);
  const p2 = LatLng(55.001, 37.000);
  const p3 = LatLng(55.001, 37.001);

  group('MeasurementUtils formatting', () {
    test('metric distance switches from meters to kilometers', () {
      expect(MeasurementUtils.formatDistance(250), '250.0 м');
      expect(MeasurementUtils.formatDistance(1500), '1.5 км');
    });

    test('metric area switches units', () {
      expect(MeasurementUtils.formatArea(500), '500 м²');
      expect(MeasurementUtils.formatArea(25000), '2.5 га');
      expect(MeasurementUtils.formatArea(2000000), '2.0 км²');
    });
  });

  group('buildMeasurementLabels ruler', () {
    test('adds a label per segment plus a total', () {
      final labels = buildMeasurementLabels(
        points: const [p1, p2, p3],
        mode: MapDrawingMode.ruler,
        metric: true,
      );

      expect(labels, hasLength(3));
      expect(labels.first.point, isNot(equals(p1)));
      expect(labels.last.text, startsWith('Итого: '));
      expect(labels.last.emphasized, isTrue);
    });

    test('splits labels across freehand segments', () {
      final labels = buildMeasurementLabels(
        points: const [p1, p2, p3],
        segments: const [
          [p1, p2],
          [p3, p1],
        ],
        mode: MapDrawingMode.ruler,
        metric: true,
      );
      // 2 сегмента + итог
      expect(labels, hasLength(3));
    });
  });

  group('buildMeasurementLabels planimeter', () {
    test('two points give only the segment distance', () {
      final labels = buildMeasurementLabels(
        points: const [p1, p2],
        mode: MapDrawingMode.planimeter,
        metric: true,
      );
      expect(labels, hasLength(1));
      expect(labels.single.text, contains('м'));
    });

    test('three points add perimeter and area', () {
      final labels = buildMeasurementLabels(
        points: const [p1, p2, p3],
        mode: MapDrawingMode.planimeter,
        metric: true,
      );

      final texts = labels.map((label) => label.text).toList();
      expect(labels, hasLength(4)); // 2 сегмента + периметр + площадь
      expect(texts.any((text) => text.startsWith('Периметр: ')), isTrue);
      expect(texts.any((text) => text.startsWith('Площадь: ')), isTrue);
    });

    test('too few points produce no labels', () {
      expect(
        buildMeasurementLabels(
          points: const [p1],
          mode: MapDrawingMode.planimeter,
          metric: true,
        ),
        isEmpty,
      );
    });
  });

  group('PaintLineData render data', () {
    test('carries the configured width', () {
      const data = PaintLineData(
        points: [p1, p2],
        color: Colors.red,
        selected: false,
        width: 6,
      );

      expect(data.width, 6);
      expect(data.haloWidth, closeTo(9.5, 0.001));
      expect(data.strokes, hasLength(1));
    });

    test('width defaults for legacy call sites', () {
      const data = PaintLineData(
        points: [p1, p2],
        color: Colors.red,
        selected: false,
      );
      expect(data.width, 3.5);
    });

    test('segments become separate strokes', () {
      const data = PaintLineData(
        points: [p1, p2, p3],
        color: Colors.blue,
        selected: true,
        width: 4,
        segments: [
          [p1, p2],
          [p3, p1],
        ],
      );

      expect(data.strokes, hasLength(2));
      expect(data.strokes.first, hasLength(2));
    });
  });

  group('Drawing model', () {
    test('stroke width survives persistence', () {
      final drawing = Drawing(
        name: 'Line',
        type: 'line',
        points: const [p1, p2],
        color: 0xFFFF0000,
        strokeWidth: 5.5,
      );

      expect(Drawing.fromMap(drawing.toMap()).strokeWidth, 5.5);
    });

    test('finish roundtrip preserves independent strokes', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);
      controller.beginFreehand(const Offset(100, 100), p3);

      final drawing = controller.finish(name: 'Multi')!;
      expect(drawing.hasSegments, isTrue);
      expect(drawing.segments, hasLength(2));
      expect(drawing.segments[0], hasLength(2));
      expect(drawing.segments[1], hasLength(1));

      final restored = Drawing.fromMap(drawing.toMap());
      expect(restored.points, hasLength(3));
      expect(restored.segmentBreaks, <int>[2]);
      expect(restored.segments, hasLength(2));
      expect(restored.segments.first.first, p1);
      expect(restored.segments.last.single, p3);
      expect(restored.strokeWidth, drawing.strokeWidth);
    });

    test('single stroke stays continuous (no breaks persisted)', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);

      final drawing = controller.finish(name: 'Single')!;
      expect(drawing.hasSegments, isFalse);
      expect(drawing.segmentBreaks, isEmpty);
      expect(drawing.segments, hasLength(1));

      final map = drawing.toMap();
      expect(jsonDecode(map['points_json'] as String), isA<List<dynamic>>());
      expect(Drawing.fromMap(map).segments, hasLength(1));
    });

    test('legacy points_json array still parses as one line', () {
      final legacy = <String, dynamic>{
        'id': 7,
        'name': 'Legacy',
        'description': null,
        'type': 'line',
        'category': 'drawing',
        'points_json': jsonEncode([
          [55.0, 37.0],
          [55.1, 37.1],
        ]),
        'geojson': '',
        'color': 0xFFFF0000,
        'stroke_width': 3.0,
        'fill_opacity': 0.5,
        'visible': 1,
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      };

      final drawing = Drawing.fromMap(legacy);
      expect(drawing.points, hasLength(2));
      expect(drawing.hasSegments, isFalse);
      expect(drawing.segments, hasLength(1));
    });

    test('out-of-range break indices are ignored', () {
      final drawing = Drawing(
        name: 'Broken',
        type: 'line',
        points: const [p1, p2, p3],
        segmentBreaks: const [0, 2, 99],
        color: 0xFFFF0000,
      );

      expect(drawing.segmentBreaks, const [0, 2, 99]);
      expect(drawing.segments, hasLength(2));
      expect(drawing.segments.last, hasLength(1));
    });
  });
}
