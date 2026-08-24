import 'package:flutter/material.dart';

enum NavigationApp { googleMaps, yandexMaps, twoGis }

class NavigationChooserSheet {
  const NavigationChooserSheet._();

  static Future<NavigationApp?> show(BuildContext context) {
    return showModalBottomSheet<NavigationApp>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            _tile(sheetContext, Icons.map, 'Google Maps',
                NavigationApp.googleMaps),
            _tile(sheetContext, Icons.map_outlined, 'Яндекс Карты',
                NavigationApp.yandexMaps),
            _tile(sheetContext, Icons.navigation, '2ГИС', NavigationApp.twoGis),
          ],
        ),
      ),
    );
  }

  static Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    NavigationApp value,
  ) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: () => Navigator.pop(context, value),
      );
}
