import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Обёртка над [TileProvider], переживающая удаление [TileLayer].
///
/// flutter_map вызывает `tileProvider.dispose()` из `_TileLayerState.dispose()`
/// (см. `tile_layer.dart`, метод `dispose`). Для провайдера, которым владеет
/// долгоживущий контроллер, это деструктивно: слой рисуется условно
/// (`if (visible) ...`), при скрытии слой удаляется и уничтожал бы провайдер
/// вместе с сессией `ImageCache`, после чего повторное включение слоя создавало
/// бы новый провайдер => повторную загрузку всех тайлов.
///
/// Обёртка делегирует `getImage`/`getImageWithCancelLoadingSupport` и делает
/// `dispose()` пустым; реальный провайдер освобождается владельцем
/// ([RetainedTileProvider.inner]).
class RetainedTileProvider extends TileProvider {
  RetainedTileProvider(this.inner) : super(headers: inner.headers);

  /// Реальный провайдер, которым владеет создатель обёртки.
  final TileProvider inner;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      inner.getImage(coordinates, options);

  @override
  bool get supportsCancelLoading => inner.supportsCancelLoading;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) =>
      inner.getImageWithCancelLoadingSupport(
        coordinates,
        options,
        cancelLoading,
      );

  @override
  Map<String, String> get headers => inner.headers;

  /// Намеренно ничего не освобождает — провайдером владеет контроллер.
  @override
  void dispose() {}
}
