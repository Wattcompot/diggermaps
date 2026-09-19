import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/constants/map_layers.dart';
import '../../providers/sentinel_controller.dart';

/// Слой спутниковых снимков с ключом по идентичности картинки.
///
/// Почему ключ включает и дату, и URL мозаики:
/// * сменить `urlTemplate` при том же `key` — значит пойти по ветке
///   `_TileLayerState.didUpdateWidget` → `reloadImages(...)`, которая
///   перезагружает уже загруженные `TileImage` (визуально — «мигание» и
///   повторная загрузка). Поэтому для новой мозаики/даты нужен **новый**
///   `key`, то есть отдельное состояние слоя;
/// * при этом старый слой не уничтожается сразу: он остаётся в дереве как
///   «retained» (с тем же `key`, значит с теми же уже загруженными тайлами) и
///   снимается, когда новая картинка реально загрузилась
///   ([SentinelController.markImageryDisplayed]) либо по таймауту;
/// * одинаковый URL (панорама в пределах покрытия) не меняет ключ вообще —
///   слой не пересобирается и тайлы не перезагружаются.
///
/// Максимум один лишний слой в дереве (retained + current).
class SentinelImageryLayer extends StatelessWidget {
  const SentinelImageryLayer({
    super.key,
    required this.controller,
    this.maxZoom = double.infinity,
    this.panBuffer = 2,
    this.keepBuffer = 3,
  });

  final SentinelController controller;

  /// Верхняя граница отображения слоя.
  ///
  /// Намеренно `infinity` по умолчанию: при `maxZoom: 19` слой исчезал целиком
  /// на зуме 20+ (`TileLayer._outsideZoomLimits`), вместо того чтобы
  /// масштабировать тайлы последнего доступного зума.
  final double maxZoom;
  final int panBuffer;
  final int keepBuffer;

  @override
  Widget build(BuildContext context) {
    if (!controller.visible) return const SizedBox.shrink();
    final current = controller.imagery;
    final retained = controller.retainedImagery;
    if (current == null && retained == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // retained снизу, current сверху.
        if (retained != null)
          _SentinelTileLayer(
            key: ValueKey<String>('sentinel-imagery-${retained.id}'),
            imagery: retained,
            controller: controller,
            isCurrent: false,
            maxZoom: maxZoom,
            panBuffer: panBuffer,
            keepBuffer: keepBuffer,
          ),
        if (current != null)
          _SentinelTileLayer(
            key: ValueKey<String>('sentinel-imagery-${current.id}'),
            imagery: current,
            controller: controller,
            isCurrent: true,
            maxZoom: maxZoom,
            panBuffer: panBuffer,
            keepBuffer: keepBuffer,
          ),
      ],
    );
  }
}

class _SentinelTileLayer extends StatefulWidget {
  const _SentinelTileLayer({
    super.key,
    required this.imagery,
    required this.controller,
    required this.isCurrent,
    required this.maxZoom,
    required this.panBuffer,
    required this.keepBuffer,
  });

  final SentinelImagery imagery;
  final SentinelController controller;
  final bool isCurrent;
  final double maxZoom;
  final int panBuffer;
  final int keepBuffer;

  @override
  State<_SentinelTileLayer> createState() => _SentinelTileLayerState();
}

class _SentinelTileLayerState extends State<_SentinelTileLayer> {
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    final imagery = widget.imagery;
    final maxNativeZoom = imagery.maxNativeZoom ?? 19;
    return TileLayer(
      urlTemplate: imagery.urlTemplate,
      tileProvider: widget.controller.tileProvider,
      minNativeZoom: imagery.minNativeZoom,
      maxNativeZoom: maxNativeZoom < imagery.minNativeZoom
          ? imagery.minNativeZoom
          : maxNativeZoom,
      maxZoom: widget.maxZoom,
      tileDimension: _safeTileDimension(imagery.tileDimension),
      panBuffer: widget.panBuffer,
      keepBuffer: widget.keepBuffer,
      tileDisplay: widget.isCurrent
          ? const TileDisplay.fadeIn(duration: Duration(milliseconds: 140))
          : const TileDisplay.instantaneous(),
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
      errorTileCallback: (_, __, ___) {},
      userAgentPackageName: MapLayers.userAgentPackageName,
      tileBuilder: widget.isCurrent ? _reportLoadedTile : null,
    );
  }

  /// Сообщаем контроллеру о прогрессе **только по реально загруженному тайлу**:
  /// `tileBuilder` вызывается и для тайлов в загрузке/с ошибкой, поэтому
  /// признаком готовности служит декодированная картинка (`imageInfo`).
  Widget _reportLoadedTile(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    if (tile.imageInfo != null && !_reported) {
      _reported = true;
      // Нельзя уведомлять слушателей во время build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller.markImageryDisplayed();
      });
    }
    return tileWidget;
  }

  static int _safeTileDimension(int value) => value == 512 ? 512 : 256;
}
