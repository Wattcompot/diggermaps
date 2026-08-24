import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/data/utils/measurement_utils.dart';

void main() {
  test('измерения корректно форматируют расстояние и площадь', () {
    expect(MeasurementUtils.formatDistance(125.04), '125.0 м');
    expect(MeasurementUtils.formatDistance(1200), '1.2 км');

    final square = <LatLng>[
      const LatLng(55.75, 37.61),
      const LatLng(55.75, 37.611),
      const LatLng(55.751, 37.611),
      const LatLng(55.751, 37.61),
    ];
    expect(MeasurementUtils.calculateArea(square), greaterThan(0));
  });
}
