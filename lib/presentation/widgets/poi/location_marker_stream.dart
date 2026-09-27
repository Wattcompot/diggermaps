import 'package:flutter/material.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';

/// ВРЕМЕННАЯ диагностика (см. `location_controller.dart`). Включается тем же
/// `--dart-define=GPS_DEBUG=true`. Удаляется вместе с логами контроллера.
const bool _kGpsDebug = bool.fromEnvironment('GPS_DEBUG');

/// Преобразует поток [Position] (geolocator) в поток для
/// [CurrentLocationLayer], сохраняя **идентичность** полученного потока между
/// пересборками, и отдаёт рядом **очищенный** поток направления.
///
/// Зачем мемоизация: `LocationMarkerDataStreamFactory.fromGeolocatorPositionStream`
/// создаёт новый объект `Stream` при каждом вызове, а `CurrentLocationLayer` в
/// `didUpdateWidget` сравнивает потоки по ссылке и при различии отменяет
/// подписку и подписывается заново. Слой живёт внутри `MapLayerStack`, который
/// пересобирается на каждый rebuild карты (жест, смена слоёв, запись трека),
/// поэтому без мемоизации подписка на позиции постоянно пересоздавалась — и
/// маячок мог пропадать. Поток пересоздаётся только тогда, когда меняется сам
/// источник (например, контроллер пересоздан).
///
/// Зачем свой поток направления: по умолчанию `CurrentLocationLayer` берёт
/// heading прямо из `flutter_rotation_sensor` без фильтрации. При
/// `markerDirection: MarkerDirection.heading` слой оборачивает маркер в
/// `Transform.rotate(angle: heading.heading)`. Если датчик ориентации на
/// устройстве отсутствует/сбоит и отдаёт `NaN`/`Infinity`, матрица поворота
/// становится нечисловой, и маркер (вместе с сектором направления) перестаёт
/// рисоваться — камера при этом уже отцентрирована, позиция дошла, а «сам
/// маркер не видно». Поэтому здесь heading очищается: некорректные значения
/// превращаются в `null`, и слой рисует маркер БЕЗ поворота, а не прячет его.
class LocationMarkerStream extends StatefulWidget {
  const LocationMarkerStream({
    super.key,
    required this.stream,
    required this.builder,
    this.headingStream,
  });

  /// Исходный поток позиций (обычно `LocationController.positionStream`).
  final Stream<Position> stream;

  /// Необязательный исходный поток направления. По умолчанию — датчик
  /// ориентации устройства (тот же, что использует пакет). Параметр нужен в
  /// первую очередь тестам, чтобы подать заведомо «битое» направление.
  final Stream<LocationMarkerHeading?>? headingStream;

  /// Строит слой маячка с уже стабильными потоками позиций и направления.
  final Widget Function(
    BuildContext context,
    Stream<LocationMarkerPosition?> positions,
    Stream<LocationMarkerHeading?> headings,
  ) builder;

  @override
  State<LocationMarkerStream> createState() => _LocationMarkerStreamState();
}

class _LocationMarkerStreamState extends State<LocationMarkerStream> {
  late Stream<LocationMarkerPosition?> _positions =
      _mapPositions(widget.stream);
  late Stream<LocationMarkerHeading?> _headings =
      _sanitizeHeading(widget.headingStream ?? _defaultHeadingSource());

  static Stream<LocationMarkerPosition?> _mapPositions(
      Stream<Position> source) {
    if (_kGpsDebug) debugPrint('[GPS] LocationMarkerStream: маппинг потока');
    return const LocationMarkerDataStreamFactory()
        .fromGeolocatorPositionStream(stream: source)
        .map((position) {
      if (_kGpsDebug) {
        debugPrint('[GPS] layer: событие для CurrentLocationLayer '
            '(${position == null ? 'null' : 'позиция'})');
      }
      return position;
    });
  }

  static Stream<LocationMarkerHeading?> _defaultHeadingSource() =>
      const LocationMarkerDataStreamFactory().fromRotationSensorHeadingStream();

  /// Отбрасывает нечисловой heading: `NaN`/`Infinity` в угле или точности
  /// превратили бы `Transform.rotate` маркера в невидимую матрицу. При
  /// некорректном значении отдаём `null` — слой покажет маркер без поворота.
  static Stream<LocationMarkerHeading?> _sanitizeHeading(
      Stream<LocationMarkerHeading?> source) {
    return source.map((heading) {
      if (heading == null) return null;
      if (!heading.heading.isFinite || !heading.accuracy.isFinite) {
        if (_kGpsDebug) {
          debugPrint('[GPS] heading: отброшено нечисловое значение '
              '(${heading.heading}) — маркер без поворота');
        }
        return null;
      }
      return heading;
    });
  }

  @override
  void didUpdateWidget(covariant LocationMarkerStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stream, widget.stream)) {
      if (_kGpsDebug) {
        debugPrint('[GPS] LocationMarkerStream: источник сменился — ремап');
      }
      _positions = _mapPositions(widget.stream);
    }
    if (!identical(oldWidget.headingStream, widget.headingStream)) {
      _headings =
          _sanitizeHeading(widget.headingStream ?? _defaultHeadingSource());
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _positions, _headings);
}
