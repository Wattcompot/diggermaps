import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/presentation/providers/drawing_controller.dart';

void main() {
  const p1 = LatLng(55.000, 37.000);
  const p2 = LatLng(55.001, 37.000);
  const p3 = LatLng(55.002, 37.000);

  group('DrawingController freehand', () {
    test('two strokes are both preserved (beginFreehand does not clear)', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);

      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);
      controller.addFreehandSample(const Offset(20, 0), p3);
      expect(controller.activeSegments, hasLength(1));

      controller.beginFreehand(const Offset(100, 100), const LatLng(56, 38));
      controller.addFreehandSample(
          const Offset(110, 100), const LatLng(56.001, 38));

      expect(controller.activeSegments, hasLength(2));
      expect(controller.activePoints, hasLength(5));
      expect(controller.activeSegments[0], hasLength(3));
      expect(controller.activeSegments[1], hasLength(2));
    });

    test('taps continue the drawing after a freehand stroke', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);

      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);
      controller.addPoint(p3);

      expect(controller.activeSegments, hasLength(1));
      expect(controller.activeSegments.last, hasLength(3));
      expect(controller.activePoints, hasLength(3));
    });

    test('too close freehand samples are skipped', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(2, 0), p2);
      expect(controller.activePoints, hasLength(1));
      controller.addFreehandSample(const Offset(20, 0), p3);
      expect(controller.activePoints, hasLength(2));
    });
  });

  group('DrawingController tap state', () {
    test('freehand samples do not arm the double-tap finish', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);

      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);
      expect(controller.lastDrawingTapAt, isNull);

      expect(controller.handleDrawingTap(p3), isFalse);
      expect(controller.lastDrawingTapAt, isNotNull);
      expect(controller.handleDrawingTap(const LatLng(55.003, 37)), isTrue);
      expect(controller.lastDrawingTapAt, isNull);
    });

    test('a single tap never finishes the drawing', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      expect(controller.handleDrawingTap(p1), isFalse);
      expect(controller.activePoints, hasLength(1));
    });
  });

  group('DrawingController undo', () {
    test('undo removes only the last point', () {
      final controller = DrawingController()..startMode(MapDrawingMode.ruler);
      controller
        ..addPoint(p1)
        ..addPoint(p2)
        ..addPoint(p3);

      controller.undo();
      expect(controller.activePoints, hasLength(2));
      expect(controller.activeSegments.single, hasLength(2));

      controller
        ..undo()
        ..undo();
      expect(controller.activePoints, isEmpty);
      expect(controller.activeSegments, isEmpty);
    });

    test('undo drops an emptied freehand stroke but keeps earlier strokes', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller.beginFreehand(Offset.zero, p1);
      controller.addFreehandSample(const Offset(10, 0), p2);
      controller.beginFreehand(const Offset(100, 100), p3);

      controller.undo();
      expect(controller.activeSegments, hasLength(1));
      expect(controller.activePoints, hasLength(2));
    });
  });

  group('DrawingController style', () {
    test('finish captures the chosen color and width', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller
        ..setColor(const Color(0xFF9C27B0))
        ..setStrokeWidth(7.5)
        ..addPoint(p1)
        ..addPoint(p2);

      final drawing = controller.finish(name: 'Line');

      expect(drawing, isNotNull);
      expect(drawing!.color, 0xFF9C27B0);
      expect(drawing.strokeWidth, 7.5);
    });

    test('stroke width is clamped to the supported range', () {
      final controller = DrawingController();
      controller.setStrokeWidth(100);
      expect(controller.strokeWidth, DrawingController.maxStrokeWidth);
      controller.setStrokeWidth(0);
      expect(controller.strokeWidth, DrawingController.minStrokeWidth);
    });

    test('palette exposes the required colors', () {
      int argb(Color color) => color.toARGB32();
      expect(DrawingController.palette.map(argb), contains(0xFFFF0000));
      expect(DrawingController.palette.map(argb), contains(0xFF2196F3));
      expect(DrawingController.palette.map(argb), contains(0xFF00A651));
      expect(DrawingController.palette.map(argb), contains(0xFFFFEB3B));
      expect(DrawingController.palette.map(argb), contains(0xFFFF9800));
      expect(DrawingController.palette.map(argb), contains(0xFF9C27B0));
      expect(DrawingController.palette.map(argb), contains(0xFFFFFFFF));
    });
  });

  group('DrawingController minimum points', () {
    test('line needs two points', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller.addPoint(p1);
      expect(controller.finish(name: 'x'), isNull);
      expect(controller.canFinish, isFalse);

      controller.addPoint(p2);
      expect(controller.canFinish, isTrue);
      expect(controller.finish(name: 'x'), isNotNull);
    });

    test('planimeter needs three points and saves as polygon measurement', () {
      final controller = DrawingController()
        ..startMode(MapDrawingMode.planimeter);
      controller
        ..addPoint(p1)
        ..addPoint(p2);
      expect(controller.finish(name: 'x'), isNull);

      controller.addPoint(p3);
      final drawing = controller.finish(name: 'x');
      expect(drawing, isNotNull);
      expect(drawing!.type, 'polygon');
      expect(drawing.category, 'measurement');
    });

    test('view mode cannot finish', () {
      final controller = DrawingController();
      expect(controller.finish(name: 'x'), isNull);
    });

    test('cancel leaves the drawing mode', () {
      final controller = DrawingController()..startMode(MapDrawingMode.line);
      controller
        ..addPoint(p1)
        ..addPoint(p2)
        ..cancel();
      expect(controller.mode, MapDrawingMode.view);
      expect(controller.activePoints, isEmpty);
    });
  });
}
