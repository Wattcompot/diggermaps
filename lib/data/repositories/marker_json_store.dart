import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/user_marker.dart';

/// Windows has no SQLite factory in this app. Keep marker CRUD durable there.
/// Mutations from all repository instances are serialized before reading disk.
class MarkerJsonStore {
  MarkerJsonStore({this.directory});

  final Directory? directory;
  static Future<void> _pending = Future.value();

  Future<T> access<T>(Future<T> Function(List<UserMarker>) action,
      {bool write = false}) {
    final result = _pending.then((_) async {
      final root = directory ?? await getApplicationDocumentsDirectory();
      await root.create(recursive: true);
      final file = File(p.join(root.path, 'user_markers.json'));
      final backup = File('${file.path}.bak');
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      final markers = <UserMarker>[];
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! List) {
          throw const FormatException('Invalid marker store');
        }
        for (final item in decoded) {
          // One damaged row must not hide every other saved marker.
          try {
            if (item is Map) {
              markers.add(UserMarker.fromMap(Map<String, dynamic>.from(item)));
            }
          } on FormatException {
            continue;
          } on TypeError {
            continue;
          }
        }
      }
      final value = await action(markers);
      if (write) {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode(markers.map((marker) => marker.toMap()).toList()),
          flush: true,
        );
        // A recoverable replacement on Windows (rename cannot overwrite).
        if (await backup.exists()) await backup.delete();
        if (await file.exists()) await file.rename(backup.path);
        await temp.rename(file.path);
        if (await backup.exists()) await backup.delete();
      }
      return value;
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
