import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

enum MarkerAction { save, share, copyCoordinates, navigation }

class MarkerActionsSheet {
  const MarkerActionsSheet._();

  static Future<MarkerAction?> show(BuildContext context, LatLng point) {
    final coordinates =
        '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
    return showModalBottomSheet<MarkerAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Сохранить метку'),
              onTap: () => Navigator.pop(sheetContext, MarkerAction.save),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Поделиться'),
              onTap: () => Navigator.pop(sheetContext, MarkerAction.share),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Копировать координаты'),
              subtitle: Text(coordinates),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: coordinates));
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, MarkerAction.copyCoordinates);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation),
              title: const Text('Навигация'),
              onTap: () => Navigator.pop(sheetContext, MarkerAction.navigation),
            ),
          ],
        ),
      ),
    );
  }
}
