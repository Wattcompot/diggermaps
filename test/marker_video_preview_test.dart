import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:digger_maps/data/models/marker_media.dart';
import 'package:digger_maps/presentation/widgets/media/marker_video_preview.dart';
import 'package:digger_maps/services/media/marker_media_service.dart';
import 'package:digger_maps/services/media/marker_media_store.dart';

/// Управляемый сервис: считает вызовы `openVideo` и воспроизводит нужный
/// исход без обращения к платформенным плагинам.
class _FakeMediaService extends MarkerMediaService {
  _FakeMediaService({required super.store});

  int openVideoCalls = 0;
  Object? openVideoError;
  Duration? openVideoDelay;
  List<MarkerMedia> openedMedia = <MarkerMedia>[];

  @override
  Future<void> openVideo(MarkerMedia media) async {
    openVideoCalls++;
    openedMedia.add(media);
    if (openVideoDelay != null) {
      await Future<void>.delayed(openVideoDelay!);
    }
    final error = openVideoError;
    if (error != null) throw error;
  }
}

MarkerMedia videoMedia({
  String ref = 'marker_media/1_clip.mp4',
  String name = 'clip.mp4',
  int? durationMs,
}) =>
    MarkerMedia(
      fileRef: ref,
      type: MarkerMedia.typeVideo,
      name: name,
      mimeType: 'video/mp4',
      createdAt: DateTime(2026, 4, 1),
      bytes: 2048,
      durationMs: durationMs,
    );

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('preview показывает Play и имя видео, открывает по тапу',
      (tester) async {
    final service = _FakeMediaService(store: MarkerMediaStore());
    final media = videoMedia(durationMs: 8000);

    await tester.pumpWidget(_host(
      MarkerVideoPreview(media: media, service: service),
    ));

    // Play affordance: иконка play и текст с именем файла.
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('Видео · Смотреть'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('00:08'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pumpAndSettle();

    expect(service.openVideoCalls, 1);
    expect(service.openedMedia.single.fileRef, media.fileRef);
  });

  testWidgets('указывает количество видео, когда их несколько', (tester) async {
    await tester.pumpWidget(_host(
      MarkerVideoPreview(media: videoMedia(), count: 3, service: null),
    ));

    expect(find.text('Видео · 3'), findsOneWidget);
    // Тап не выполняется: сервис не передан, внешнее открытие не вызывается.
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  testWidgets('ошибка открытия показывается пользователю', (tester) async {
    final service = _FakeMediaService(store: MarkerMediaStore())
      ..openVideoError = StateError('Видео недоступно');

    await tester.pumpWidget(
      _host(MarkerVideoPreview(media: videoMedia(), service: service)),
    );
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pumpAndSettle();

    // Понятная ошибка из describeError, а не исключение наружу.
    expect(find.text('Видео недоступно'), findsOneWidget);

    // Кнопка снова доступна: busy-состояние сброшено.
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('повторный тап во время открытия не дублирует вызов',
      (tester) async {
    final service = _FakeMediaService(store: MarkerMediaStore())
      ..openVideoDelay = const Duration(milliseconds: 300);

    await tester.pumpWidget(
      _host(MarkerVideoPreview(media: videoMedia(), service: service)),
    );

    await tester.tap(find.byIcon(Icons.play_circle_fill));
    await tester.pump();

    // Пока идёт открытие — индикатор вместо Play, и повторные тапы
    // игнорируются. Тапаем по самому виджету: он не меняет размер.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(MarkerVideoPreview));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.openVideoCalls, 1);
  });

  testWidgets('виджет остаётся компактным', (tester) async {
    await tester.pumpWidget(_host(
      SizedBox(width: 320, child: MarkerVideoPreview(media: videoMedia())),
    ));

    final height = tester.getSize(find.byType(MarkerVideoPreview)).height;
    // Компактная строка, а не огромный video-блок в карточке.
    expect(height, lessThan(72));
    expect(height, greaterThanOrEqualTo(48));
  });
}
