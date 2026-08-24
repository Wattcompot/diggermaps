import 'package:flutter/material.dart';

enum AddMapAction { marker, line, ruler, planimeter, recordTrack }

class AddActionsSheet {
  const AddActionsSheet._();

  static Future<AddMapAction?> show(BuildContext context) {
    return showModalBottomSheet<AddMapAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            _tile(sheetContext, Icons.location_pin, 'Поставить метку',
                AddMapAction.marker),
            _tile(sheetContext, Icons.edit, 'Нарисовать линию',
                AddMapAction.line),
            _tile(
                sheetContext, Icons.straighten, 'Линейка', AddMapAction.ruler),
            _tile(sheetContext, Icons.square_foot, 'Планиметр',
                AddMapAction.planimeter),
            _tile(sheetContext, Icons.fiber_manual_record, 'Записать трек',
                AddMapAction.recordTrack),
          ],
        ),
      ),
    );
  }

  static Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    AddMapAction value,
  ) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: () => Navigator.pop(context, value),
      );
}
