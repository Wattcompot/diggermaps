import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:digger_maps/data/models/user_marker.dart';
import 'package:digger_maps/presentation/widgets/bottom_sheets/marker_style_picker_sheet.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_builder.dart';
import 'package:digger_maps/presentation/widgets/poi/marker_shape.dart';
import 'package:digger_maps/presentation/widgets/poi/object_preview_card.dart';
import 'package:digger_maps/presentation/widgets/poi/object_preview_layer.dart';
import 'package:digger_maps/presentation/widgets/poi/user_marker_layer.dart';

void main() {
  testWidgets(
      'shared preview replaces marker, closes smoothly and leaves map gestures available',
      (tester) async {
    final preview = ObjectPreviewController();
    final map = MapController();
    var opened = 0;
    var mapTaps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FlutterMap(
      mapController: map,
      options: MapOptions(
          initialCenter: const LatLng(0, 0),
          initialZoom: 15,
          onTap: (_, __) => mapTaps++),
      children: <Widget>[
        UserMarkerLayer(
            markers: <UserMarker>[
              UserMarker(
                  id: 1,
                  name: 'Метка',
                  lat: 0,
                  lng: 0,
                  colorHex: '#C4956A',
                  size: 24),
            ],
            onMarkerTap: (_) => opened++,
            onMarkerLongPress: (_) {},
            previewController: preview),
        ObjectPreviewLayer(controller: preview),
      ],
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('marker-1')));
    await tester.pumpAndSettle();
    expect(find.text('Метка'), findsOneWidget);
    expect(opened, 0);
    for (final name in ['Рисунок', 'Измерение', 'Трек']) {
      preview.toggle(ObjectPreview(
          id: name,
          point: const LatLng(0, 0),
          child: ObjectPreviewCard(
              leading: const Icon(Icons.gesture),
              title: name,
              onClose: preview.hide,
              onTap: () {
                opened++;
                preview.hide();
              })));
      await tester.pumpAndSettle();
      expect(find.text('Метка'), findsNothing);
      expect(find.byType(ObjectPreviewCard), findsOneWidget);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.text(name), findsNothing);
    }
    expect(opened, 3);
    preview.toggle(ObjectPreview(
        id: 'drawing',
        point: const LatLng(0, 0),
        child: ObjectPreviewCard(
            leading: const Icon(Icons.gesture),
            title: 'Рисунок',
            onTap: () {},
            onClose: preview.hide)));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 40));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(mapTaps, 1,
        reason: 'Empty space above a card must pass taps to the map');
    final before = map.camera.center;
    await tester.dragFrom(const Offset(100, 400), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(map.camera.center, isNot(before));
    await tester.tap(find.byTooltip('Скрыть'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Рисунок'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Рисунок'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    preview.dispose();
    map.dispose();
  });

  testWidgets(
      'appearance preview immediately reflects shape, color and three sizes',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MarkerStylePickerSheet(
      point: LatLng(0, 0),
      initialShape: 'pin',
      initialColor: '#C4956A',
      initialSize: 32,
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    await tester.tap(find.text('Большой'));
    await tester.pumpAndSettle();
    expect(tester.widget<MarkerShape>(find.byType(MarkerShape).first).size, 48);
    await tester.tap(find.text('Форма'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Звезда'));
    await tester.pumpAndSettle();
    expect(tester.widget<MarkerShape>(find.byType(MarkerShape).first).shape,
        'star');
    await tester.tap(find.text('Цвет'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Синий'));
    await tester.tap(find.byTooltip('Синий'));
    await tester.pumpAndSettle();
    expect(tester.widget<MarkerShape>(find.byType(MarkerShape).first).color,
        const Color(0xFF2196F3));
    expect(tester.takeException(), isNull);
  });

  test('small marker keeps its glyph size inside a 44 dp hitbox', () {
    final marker = UserMarker(
        name: 'Метка', lat: 0, lng: 0, colorHex: '#C4956A', size: 24);
    final built = MarkerBuilder.buildMapMarker(
        marker: marker, selected: false, onTap: () {});
    expect(built.width, 44);
    expect(built.height, 44);
    final center = (built.child as GestureDetector).child! as Center;
    expect((center.child! as MarkerBuilder).marker.size, 24);
  });
}
