import 'package:digger_maps/presentation/widgets/poi/coordinate_grid_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('шаг сетки «красивый» и уменьшается с ростом зума', () {
    final far = CoordinateGridSpec.forCamera(
      latitude: 55.75,
      zoom: 8,
      metricUnits: true,
    );
    final near = CoordinateGridSpec.forCamera(
      latitude: 55.75,
      zoom: 16,
      metricUnits: true,
    );

    expect(near.stepMeters, lessThan(far.stepMeters));
    expect(CoordinateGridGeometry.metricStepsMeters, contains(far.stepMeters));
    expect(CoordinateGridGeometry.metricStepsMeters, contains(near.stepMeters));
  });

  test('меридианы реже по градусам на высоких широтах', () {
    final equator = CoordinateGridSpec.forCamera(
      latitude: 0,
      zoom: 12,
      metricUnits: true,
    );
    final north = CoordinateGridSpec.forCamera(
      latitude: 70,
      zoom: 12,
      metricUnits: true,
    );

    // На экваторе ячейка квадратная (меридианы и параллели по градусам равны),
    // у полюса меридианы идут заметно реже по градусам.
    expect(equator.lngStepDegrees, closeTo(equator.latStepDegrees, 1e-12));
    expect(north.lngStepDegrees, greaterThan(north.latStepDegrees));
    expect(north.lngStepDegrees / north.latStepDegrees, greaterThan(2));
  });

  test('имперский режим берёт шаги в футах/милях', () {
    final imperial = CoordinateGridSpec.forCamera(
      latitude: 40,
      zoom: 14,
      metricUnits: false,
    );
    final metric = CoordinateGridSpec.forCamera(
      latitude: 40,
      zoom: 14,
      metricUnits: true,
    );

    expect(
      CoordinateGridGeometry.imperialStepsFeet.map((feet) => feet * 0.3048),
      contains(imperial.stepMeters),
    );
    expect(imperial.stepMeters, isNot(metric.stepMeters));
    expect(CoordinateGridGeometry.formatStep(500, true), '500 м');
    expect(CoordinateGridGeometry.formatStep(1000, true), '1 км');
    expect(CoordinateGridGeometry.formatStep(1000, false), contains('фут'));
    expect(CoordinateGridGeometry.formatStep(5280 * 0.3048, false),
        contains('миль'));
  });

  test('количество линий ограничено даже на весь мир (зум 0)', () {
    final spec = CoordinateGridSpec.forCamera(
      latitude: 0,
      zoom: 0,
      metricUnits: true,
    );
    final lines = CoordinateGridLines.build(
      south: -85.0511287798,
      north: 85.0511287798,
      west: -180,
      east: 180,
      spec: spec,
      maxLines: 96,
    );

    expect(lines.latitudes, isNotEmpty);
    expect(lines.longitudes, isNotEmpty);
    expect(lines.latitudes.length, lessThanOrEqualTo(96));
    expect(lines.longitudes.length, lessThanOrEqualTo(96));
  });

  test('широта линий не выходит за границы Меркатора', () {
    final spec = CoordinateGridSpec.forCamera(
      latitude: 80,
      zoom: 4,
      metricUnits: true,
    );
    final lines = CoordinateGridLines.build(
      south: -89,
      north: 89,
      west: -179,
      east: 179,
      spec: spec,
      maxLines: 96,
    );

    expect(lines.latitudes, isNotEmpty);
    for (final latitude in lines.latitudes) {
      expect(
        latitude.abs(),
        lessThanOrEqualTo(CoordinateGridGeometry.maxLatitude + 1e-9),
      );
    }
  });

  test('линии привязаны к миру: координаты кратны шагу', () {
    final spec = CoordinateGridSpec.forCamera(
      latitude: 55.75,
      zoom: 12,
      metricUnits: true,
    );
    final lines = CoordinateGridLines.build(
      south: 55,
      north: 56,
      west: 37,
      east: 38,
      spec: spec,
      maxLines: 96,
    );

    expect(lines.latitudes, isNotEmpty);
    expect(lines.longitudes, isNotEmpty);
    for (final latitude in lines.latitudes) {
      final ratio = latitude / lines.latStepDegrees;
      expect((ratio - ratio.roundToDouble()).abs(), lessThan(1e-9));
    }
    for (final longitude in lines.longitudes) {
      final ratio = longitude / lines.lngStepDegrees;
      expect((ratio - ratio.roundToDouble()).abs(), lessThan(1e-9));
    }
  });

  test('wrapLongitude приводит долготу к [-180, 180)', () {
    expect(CoordinateGridGeometry.wrapLongitude(190), closeTo(-170, 1e-9));
    expect(CoordinateGridGeometry.wrapLongitude(-190), closeTo(170, 1e-9));
    expect(CoordinateGridGeometry.wrapLongitude(180), closeTo(-180, 1e-9));
    expect(CoordinateGridGeometry.wrapLongitude(37.6), closeTo(37.6, 1e-9));
  });

  test('точность подписи зависит от шага', () {
    expect(CoordinateGridGeometry.decimalsForStep(1), 0);
    expect(CoordinateGridGeometry.decimalsForStep(0.05), 2);
    expect(CoordinateGridGeometry.decimalsForStep(0.0002), 4);
  });
}
