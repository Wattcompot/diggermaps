import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/drawing.dart';

enum MapDrawingMode { view, line, polygon, ruler, planimeter }

class DrawingController extends ChangeNotifier {
  MapDrawingMode _drawingMode = MapDrawingMode.view;
  final List<LatLng> _activePoints = <LatLng>[];
  Offset? _lastLineSampleOffset;
  DateTime? _lastDrawingTapAt;
  Color _drawingColor = Colors.red;
  final double _strokeWidth = 3;

  MapDrawingMode get mode => _drawingMode;
  List<LatLng> get activePoints => List<LatLng>.unmodifiable(_activePoints);
  Offset? get lastLineSampleOffset => _lastLineSampleOffset;
  DateTime? get lastDrawingTapAt => _lastDrawingTapAt;
  Color get color => _drawingColor;
  double get strokeWidth => _strokeWidth;
  bool get isActive => _drawingMode != MapDrawingMode.view;

  Color colorForMode(MapDrawingMode mode) => switch (mode) {
        MapDrawingMode.line => Colors.red,
        MapDrawingMode.polygon => Colors.cyan,
        MapDrawingMode.planimeter => Colors.cyan,
        MapDrawingMode.ruler => Colors.green,
        MapDrawingMode.view => Colors.red,
      };

  String get modeLabel => switch (_drawingMode) {
        MapDrawingMode.line => 'Линия',
        MapDrawingMode.polygon => 'Многоугольник',
        MapDrawingMode.ruler => 'Линейка',
        MapDrawingMode.planimeter => 'Планиметр',
        MapDrawingMode.view => '',
      };

  void startMode(MapDrawingMode mode) {
    _drawingMode = mode;
    _drawingColor = colorForMode(mode);
    _activePoints.clear();
    _lastLineSampleOffset = null;
    notifyListeners();
  }

  void beginFreehand(Offset offset, LatLng point) {
    _lastLineSampleOffset = offset;
    _activePoints
      ..clear()
      ..add(point);
    notifyListeners();
  }

  void addFreehandSample(Offset offset, LatLng point) {
    final previous = _lastLineSampleOffset;
    if (previous != null && (offset - previous).distance < 6) return;
    _lastLineSampleOffset = offset;
    addPoint(point);
  }

  void addPoint(LatLng point) {
    _activePoints.add(point);
    _lastDrawingTapAt = DateTime.now();
    notifyListeners();
  }

  void undo() {
    if (_activePoints.isEmpty) return;
    _activePoints.removeLast();
    notifyListeners();
  }

  void clear() {
    _activePoints.clear();
    _lastLineSampleOffset = null;
    notifyListeners();
  }

  Drawing? finish({required String name}) {
    if (_drawingMode == MapDrawingMode.view || _activePoints.length < 2) {
      return null;
    }
    if ((_drawingMode == MapDrawingMode.polygon ||
            _drawingMode == MapDrawingMode.planimeter) &&
        _activePoints.length < 3) {
      return null;
    }
    final mode = _drawingMode;
    return Drawing(
      name: name,
      type: mode == MapDrawingMode.planimeter || mode == MapDrawingMode.polygon
          ? 'polygon'
          : 'line',
      points: List<LatLng>.from(_activePoints),
      color: mode == MapDrawingMode.line
          ? const Color(0xFFFF0000).toARGB32()
          : colorForMode(mode).toARGB32(),
      strokeWidth: mode == MapDrawingMode.line ? 3.5 : _strokeWidth,
      fillOpacity: 0.3,
      category:
          mode == MapDrawingMode.ruler || mode == MapDrawingMode.planimeter
              ? 'measurement'
              : 'drawing',
    );
  }

  void cancel() {
    _activePoints.clear();
    _lastLineSampleOffset = null;
    _drawingMode = MapDrawingMode.view;
    notifyListeners();
  }
}
