import 'package:flutter/material.dart';

Future<bool> confirmObjectDelete(
  BuildContext context, {
  required String type,
  required String name,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Удалить $type?'),
      content: Text('«$name» будет удалён безвозвратно.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
