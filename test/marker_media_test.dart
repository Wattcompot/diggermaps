import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/data/models/user_marker.dart';

MarkerMedia _photo({String ref = 'marker_media/1_ab.jpg'}) => MarkerMedia(
      fileRef: ref,
      type: MarkerMedia.typePhoto,
      name: 'hole.jpg',
      mimeType: 'image/jpeg',
      createdAt: DateTime(2026, 5, 1, 10, 30),
      bytes: 2048,
    );

MarkerMedia _voice({String ref = 'marker_media/2_cd.wav'}) => MarkerMedia(
      fileRef: ref,
      type: MarkerMedia.typeVoice,
      name: 'Голосовая заметка.wav',
      mimeType: 'audio/wav',
      createdAt: DateTime(2026, 5, 1, 10, 31),
      bytes: 4096,
      durationMs: 65000,
    );

void main() {
  group('MarkerMedia', () {
    test('сериализуется ссылкой на файл, а не содержимым', () {
      final json = jsonEncode(_photo().toMap());
      expect(json, contains('marker_media/1_ab.jpg'));
      expect(json, contains('image/jpeg'));
      // Размер файла — это метаданные, а не сами байты.
      expect(json, contains('2048'));
      expect(json.contains('base64'), isFalse);
      expect(json.contains('data:image'), isFalse);
      expect(json.length, lessThan(300));
    });

    test('переживает round-trip через map', () {
      final original = _voice();
      final restored = MarkerMedia.fromMap(original.toMap());
      expect(restored.fileRef, original.fileRef);
      expect(restored.type, MarkerMedia.typeVoice);
      expect(restored.mimeType, 'audio/wav');
      expect(restored.bytes, 4096);
      expect(restored.durationMs, 65000);
      expect(restored.createdAt, original.createdAt);
      expect(restored.isVoice, isTrue);
      expect(restored.isPhoto, isFalse);
    });

    test('отклоняет пустую ссылку и неизвестный тип', () {
      expect(
        () => MarkerMedia.fromMap(
            <String, dynamic>{'file_ref': '', 'type': 'photo'}),
        throwsFormatException,
      );
      expect(
        () => MarkerMedia.fromMap(<String, dynamic>{
          'file_ref': 'marker_media/1.jpg',
          'type': 'unknown',
        }),
        throwsFormatException,
      );
    });

    test('старая метка без медиа декодируется в пустой список', () {
      expect(MarkerMedia.decodeList(null), isEmpty);
      expect(MarkerMedia.decodeList(''), isEmpty);
      expect(MarkerMedia.decodeList('{}'), isEmpty);
      expect(MarkerMedia.decodeList('не json'), isEmpty);
    });

    test('повреждённая запись не скрывает остальные', () {
      final decoded = MarkerMedia.decodeList(jsonEncode(<dynamic>[
        _photo().toMap(),
        <String, dynamic>{'file_ref': '', 'type': 'photo'},
        <String, dynamic>{'type': 'voice'},
        _voice().toMap(),
        'мусор',
      ]));
      expect(decoded.length, 2);
      expect(decoded.first.isPhoto, isTrue);
      expect(decoded.last.isVoice, isTrue);
    });

    test('длительность голосовой заметки показывается как mm:ss', () {
      expect(_voice().durationLabel, '01:05');
      expect(
        _photo().durationLabel,
        '--:--',
      );
    });
  });

  group('UserMarker с медиа', () {
    test('пишет ссылки в media_json', () {
      final marker = UserMarker(
        id: 7,
        name: 'Яма',
        description: 'Глубокая',
        lat: 55.75,
        lng: 37.61,
        colorHex: '#A67B5B',
        media: <MarkerMedia>[_photo(), _voice()],
      );
      final map = marker.toMap();
      final media = jsonDecode(map['media_json'] as String) as List<dynamic>;
      expect(media.length, 2);
      expect((media.first as Map<String, dynamic>)['file_ref'],
          'marker_media/1_ab.jpg');
      expect(marker.photoCount, 1);
      expect(marker.voiceCount, 1);
      expect(marker.hasMedia, isTrue);

      final restored = UserMarker.fromMap(map);
      expect(restored.media.length, 2);
      expect(restored.media.first.fileRef, 'marker_media/1_ab.jpg');
      expect(restored.name, 'Яма');
    });

    test('старая строка таблицы остаётся читаемой', () {
      final legacy = UserMarker.fromMap(<String, dynamic>{
        'id': 3,
        'title': 'Старая метка',
        'desc': 'из первой версии',
        'latitude': 55.1,
        'longitude': 37.2,
        'color': '#FF0000',
        'icon': 'flag',
        'group': 'Клады',
      });
      expect(legacy.name, 'Старая метка');
      expect(legacy.description, 'из первой версии');
      expect(legacy.lat, 55.1);
      expect(legacy.lng, 37.2);
      expect(legacy.shape, 'flag');
      expect(legacy.media, isEmpty);
      expect(legacy.hasMedia, isFalse);
    });

    test('строки без media_json не ломают разбор', () {
      final marker = UserMarker.fromMap(<String, dynamic>{
        'id': 1,
        'name': 'Без вложений',
        'lat': 0.0,
        'lng': 0.0,
        'color_hex': '#000000',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(marker.media, isEmpty);
      expect(MarkerMedia.decodeList(marker.toMap()['media_json']), isEmpty);
    });

    test('copyWith сохраняет список вложений', () {
      final marker = UserMarker(
        name: 'A',
        lat: 1,
        lng: 2,
        colorHex: '#FFFFFF',
        media: <MarkerMedia>[_photo()],
      );
      final renamed = marker.copyWith(name: 'B');
      expect(renamed.media.length, 1);
      expect(
        () => renamed.media.add(_photo()),
        throwsUnsupportedError,
      );
    });
  });
}
