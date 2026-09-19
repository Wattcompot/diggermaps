import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/drawing.dart';

enum MapDrawingMode { view, line, polygon, ruler, planimeter }

/// Единственный источник состояния рисования/измерения.
///
/// Ключевые инварианты:
/// * [_activeSegments] хранит отдельные штрихи (один pan = один штрих).
///   [beginFreehand] больше НЕ очищает предыдущие точки, поэтому рисунок
///   накапливается, а не затирается.
/// * [_activePoints] — плоский список всех точек (сумма сегментов). Он сохранён
///   для обратной совместимости с существующими слоями.
/// * Состояние tap/double-tap ([_lastDrawingTapAt]) обновляется только
///   настоящими тапами. Свободное рисование его не трогает, а [beginFreehand]
///   сбрасывает, чтобы жест pan не «притворялся» вторым тапом.
class DrawingController extends ChangeNotifier {
  /// Палитра стилей, доступная во время создания объекта.
  static const List<Color> palette = <Color>[
    Color(0xFFFF0000), // red
    Color(0xFF2196F3), // blue
    Color(0xFF00A651), // green
    Color(0xFFFFEB3B), // yellow
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFFFFFFFF), // white
  ];

  static const double minStrokeWidth = 1.0;
  static const double maxStrokeWidth = 12.0;
  static const double defaultStrokeWidth = 3.0;
  static const Duration doubleTapWindow = Duration(milliseconds: 350);

  MapDrawingMode _drawingMode = MapDrawingMode.view;
  final List<LatLng> _activePoints = <LatLng>[];
  final List<List<LatLng>> _activeSegments = <List<LatLng>>[];
  Offset? _lastLineSampleOffset;
  DateTime? _lastDrawingTapAt;
  Color _drawingColor = Colors.red;
  double _strokeWidth = defaultStrokeWidth;

  MapDrawingMode get mode => _drawingMode;
  List<LatLng> get activePoints => List<LatLng>.unmodifiable(_activePoints);

  /// Разбивка активного рисунка на штрихи (pan-сегменты и tap-серии).
  List<List<LatLng>> get activeSegments => _activeSegments
      .map((segment) => List<LatLng>.unmodifiable(segment))
      .toList(growable: false);

  Offset? get lastLineSampleOffset => _lastLineSampleOffset;
  DateTime? get lastDrawingTapAt => _lastDrawingTapAt;
  Color get color => _drawingColor;
  double get strokeWidth => _strokeWidth;
  bool get isActive => _drawingMode != MapDrawingMode.view;

  /// Минимум точек, при котором режим можно завершить.
  int minimumPointsFor(MapDrawingMode mode) => switch (mode) {
        MapDrawingMode.polygon || MapDrawingMode.planimeter => 3,
        MapDrawingMode.line || MapDrawingMode.ruler => 2,
        MapDrawingMode.view => 0,
      };

  bool get canFinish =>
      _drawingMode != MapDrawingMode.view &&
      _activePoints.length >= minimumPointsFor(_drawingMode);

  Color colorForMode(MapDrawingMode mode) => switch (mode) {
        MapDrawingMode.line => Colors.red,
        MapDrawingMode.polygon => Colors.cyan,
        MapDrawingMode.planimeter => Colors.cyan,
        MapDrawingMode.ruler => Colors.green,
        MapDrawingMode.view => Colors.red,
      };

  bool isAreaMode(MapDrawingMode mode) =>
      mode == MapDrawingMode.polygon || mode == MapDrawingMode.planimeter;

  String get modeLabel => switch (_drawingMode) {
        MapDrawingMode.line => 'Линия',
        MapDrawingMode.polygon => 'Многоугольник',
        MapDrawingMode.ruler => 'Линейка',
        MapDrawingMode.planimeter => 'Планиметр',
        MapDrawingMode.view => '',
      };

  /// Старт нового режима: сбрасывает активный рисунок и цвет на дефолт режима.
  void startMode(MapDrawingMode mode) {
    _drawingMode = mode;
    _drawingColor = colorForMode(mode);
    _strokeWidth = defaultStrokeWidth;
    _resetActive();
    notifyListeners();
  }

  /// Начало свободного штриха. Предыдущие сегменты сохраняются: каждый pan
  /// добавляет новый штрих, а не затирает рисунок.
  void beginFreehand(Offset offset, LatLng point) {
    _lastLineSampleOffset = offset;
    // Жест рисования отделён от double-tap детекции тапов.
    _lastDrawingTapAt = null;
    _activeSegments.add(<LatLng>[point]);
    _activePoints.add(point);
    notifyListeners();
  }

  /// Продолжение свободного штриха. Не влияет на tap-состояние.
  void addFreehandSample(Offset offset, LatLng point) {
    final previous = _lastLineSampleOffset;
    if (previous != null && (offset - previous).distance < 6) return;
    _lastLineSampleOffset = offset;
    _appendPoint(point);
    notifyListeners();
  }

  /// Тап в режиме рисования: продолжает текущий штрих (или начинает новый).
  void addPoint(LatLng point) {
    _lastDrawingTapAt = DateTime.now();
    _appendPoint(point);
    notifyListeners();
  }

  /// Обрабатывает тап и сообщает, нужно ли завершить рисование (double-tap).
  bool handleDrawingTap(LatLng point) {
    final now = DateTime.now();
    final previous = _lastDrawingTapAt;
    final isDoubleTap =
        previous != null && now.difference(previous) < doubleTapWindow;
    if (isDoubleTap) {
      // Поглощаем окно, чтобы третий тап не завершил повторно.
      _lastDrawingTapAt = null;
      return true;
    }
    addPoint(point);
    return false;
  }

  /// Отменяет последнюю точку. Не очищает рисунок целиком.
  void undo() {
    if (_activePoints.isEmpty) return;
    if (_activeSegments.isNotEmpty) {
      final last = _activeSegments.last;
      if (last.isNotEmpty) last.removeLast();
      if (last.isEmpty) _activeSegments.removeLast();
    }
    _activePoints.removeLast();
    _lastLineSampleOffset = null;
    _lastDrawingTapAt = null;
    notifyListeners();
  }

  void setColor(Color color) {
    if (color.toARGB32() == _drawingColor.toARGB32()) return;
    _drawingColor = color;
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    final clamped = width.clamp(minStrokeWidth, maxStrokeWidth).toDouble();
    if (clamped == _strokeWidth) return;
    _strokeWidth = clamped;
    notifyListeners();
  }

  /// Полная очистка активных точек (оставаясь в текущем режиме).
  void clear() {
    _resetActive();
    notifyListeners();
  }

  Drawing? finish({required String name}) {
    if (!canFinish) return null;
    final mode = _drawingMode;
    final isArea = isAreaMode(mode);
    return Drawing(
      name: name,
      type: isArea ? 'polygon' : 'line',
      points: List<LatLng>.from(_activePoints),
      // Разрывы между независимыми штрихами сохраняются, иначе после
      // сохранения линия соединила бы отдельные stroke'и.
      segmentBreaks: _segmentBreaks(),
      color: _drawingColor.toARGB32(),
      strokeWidth: _strokeWidth,
      fillOpacity: 0.3,
      category:
          mode == MapDrawingMode.ruler || mode == MapDrawingMode.planimeter
              ? 'measurement'
              : 'drawing',
    );
  }

  /// Стартовые индексы всех штрихов, кроме первого.
  List<int> _segmentBreaks() {
    final breaks = <int>[];
    var index = 0;
    for (final segment in _activeSegments) {
      if (segment.isEmpty) continue;
      if (index > 0) breaks.add(index);
      index += segment.length;
    }
    return breaks;
  }

  /// Выход из режима с полной очисткой.
  void cancel() {
    _resetActive();
    _drawingMode = MapDrawingMode.view;
    notifyListeners();
  }

  void _appendPoint(LatLng point) {
    if (_activeSegments.isEmpty) _activeSegments.add(<LatLng>[]);
    _activeSegments.last.add(point);
    _activePoints.add(point);
  }

  void _resetActive() {
    _activePoints.clear();
    _activeSegments.clear();
    _lastLineSampleOffset = null;
    _lastDrawingTapAt = null;
  }
}
