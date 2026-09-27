import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_notifications.dart';
import '../app_scroll.dart';

/// Единая раскладка оверлеев карты (низ, боковой рейл и карточка записи).
///
/// Зачем: раньше каждый оверлей (`BottomActions`, `RecordingOverlay`,
/// `SpectralStatusChip`, `CalibrationControls`, `LeftPanel`) позиционировал
/// себя сам через `Positioned` с «магическими» отступами
/// (`bottom: 100`, `bottom: spectralVisible ? 72 : 16`, `top: 150`). Любое
/// изменение высоты соседа (появился chip снимков, включилась калибровка)
/// или масштаба текста ломало эту арифметику и приводило к наложениям.
///
/// Здесь всё собирается настоящими `Column`/`Row` с фактическими высотами:
///
/// ```text
/// ┌──────────────────────────────────────────────────┐
/// │ верхняя область (Expanded)                       │
/// │   LeftPanel (сверху ~25%)      карточка записи   │
/// ├──────────────────────────────────────────────────┤
/// │ нижняя стопка (снизу):                           │
/// │   primaryPanel (калибровка | прицеливание)  │    │ ← trailing
/// │   panels (контролы записи, chip снимков)    │    │   (экшен-рейл)
/// └──────────────────────────────────────────────────┘   справа
/// ```
///
/// Гарантии:
///  * нижняя стопка не поднимается выше центра экрана при прицеливании
///    ([aimingMaxExtentFactor]) и выше [maxExtentFactor] в остальных
///    случаях — crosshair и карта остаются видимыми;
///  * при прицеливании дополнительно резервируется [notificationReserve] —
///    место под уведомление над кнопками, чтобы SnackBar не перекрывал прицел;
///  * если содержимое выше лимита, стопка не «переполняется», а
///    прокручивается со штатным общим scrollbar'ом ([appScrollBehavior]);
///  * [leftPanel] живёт в той же раскладке и не может пересечь нижнюю
///    стопку — верхняя область заканчивается ровно там, где она начинается;
///  * пустые участки не перехватывают нажатия — карта остаётся управляемой.
///
/// Виджет возвращает [Positioned.fill], поэтому должен быть прямым потомком
/// `Stack` (в `MapScreen` это `body: Stack(...)`).
class MapBottomDock extends StatelessWidget {
  const MapBottomDock({
    super.key,
    this.leftPanel,
    this.stats,
    this.primaryPanel,
    this.panels = const <Widget>[],
    this.trailing,
    this.aiming = false,
    this.leftPanelTopFactor = 0.25,
    this.statsTopOffset = 138,
    this.maxExtentFactor = 0.62,
    this.aimingMaxExtentFactor = 0.5,
    this.notificationReserve = 0,
    this.crosshairGap = _defaultCrosshairGap,
    this.panelGap = 8,
    this.railGap = 24,
    this.horizontalPadding = 16,
    this.topPadding = 12,
    this.bottomPadding = 16,
  });

  /// Левый рейл инструментов (`LeftPanel` в режиме содержимого), сверху
  /// [leftPanelTopFactor] от высоты экрана. Прокручивается, если не влезает.
  final Widget? leftPanel;

  /// Карточка статистики записи трека (`TrackRecordingStatsCard`).
  final Widget? stats;

  /// Главная панель стопки: панель калибровки либо кнопки прицеливания.
  final Widget? primaryPanel;

  /// Панели под главной: контролы записи, chip спутниковых снимков.
  /// Сами скрываются (анимацией), поэтому список можно задавать статически.
  final List<Widget> panels;

  /// Экшен-рейл по умолчанию (GPS/Сдвиг/Карты), выравнивается по низу
  /// стопки. Обычно `null` при прицеливании и калибровке.
  final Widget? trailing;

  /// Режим прицеливания: включает защиту центра экрана под crosshair.
  final bool aiming;

  /// Доля высоты экрана, на которой начинается левый рейл (как было раньше).
  final double leftPanelTopFactor;

  /// Отступ карточки статистики от верхней границы оверлея. Соответствует
  /// блоку верхнего бара (`TopBar` + `OpacityControl`), который живёт в
  /// `map_screen` и здесь не измеряется, поэтому значение вынесено в параметр.
  final double statsTopOffset;

  /// Максимальная высота нижней стопки как доля высоты экрана.
  final double maxExtentFactor;

  /// То же для режима прицеливания: 0.5 держит стопку строго ниже центра.
  final double aimingMaxExtentFactor;

  /// Запас высоты под уведомление над нижней стопкой в режиме прицеливания.
  ///
  /// Тематический SnackBar рисует хост уведомлений, прижимая его к верху
  /// нижней стопки. Чтобы уведомление не залезло на прицел, стопка
  /// укорачивается на эту величину: над кнопками остаётся место под плашку.
  /// Обычно сюда передают фактическую высоту тематического SnackBar
  /// ([AppNotifications.themedSnackBarHeight]); вне прицеливания не влияет.
  final double notificationReserve;

  /// Дополнительный зазор до центра экрана в режиме прицеливания.
  ///
  /// Учитывает размер самого прицела: `CrosshairPainter` оставляет разрыв
  /// 22 лог. пикселя вокруг центра, поэтому стопка не должна подниматься
  /// ближе, чем на это расстояние.
  final double crosshairGap;

  static const double _defaultCrosshairGap = 28;

  /// Зазор между панелями нижней стопки.
  final double panelGap;

  /// Зазор между стопкой и экшен-рейлом (24 сохраняет прежние `right: 88`).
  final double railGap;

  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = media.padding;
    final screen = media.size;
    final topInset = insets.top + topPadding;
    final bottomInset = insets.bottom + bottomPadding;
    final factor = aiming ? aimingMaxExtentFactor : maxExtentFactor;

    // Верхний край нижней стопки не доходит до центра экрана: там crosshair,
    // и в любом случае половина карты остаётся доступной. В прицеливании
    // дополнительно резервируем высоту под уведомление: SnackBar висит над
    // стопкой и не должен перекрывать прицел.
    final reserve = aiming ? math.max(0.0, notificationReserve) : 0.0;
    final guard = screen.height * factor - bottomInset - crosshairGap - reserve;

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topInset,
          horizontalPadding,
          bottomInset,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = math.max(0.0, constraints.maxHeight);
            final bottomExtent = math.max(0.0, math.min(available, guard));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _buildUpperArea(screen, topInset)),
                _buildBottomArea(bottomExtent, bottomInset),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildUpperArea(Size screen, double topInset) {
    if (leftPanel == null && stats == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final upper = math.max(0.0, constraints.maxHeight);
        final railTop = math.min(
          math.max(0.0, screen.height * leftPanelTopFactor - topInset),
          upper,
        );
        final statsTop = math.min(statsTopOffset, upper);
        return Stack(
          children: <Widget>[
            if (leftPanel != null)
              Positioned(
                left: 0,
                top: railTop,
                child: _DockScrollArea(
                  maxExtent: upper - railTop,
                  child: leftPanel!,
                ),
              ),
            if (stats != null)
              Positioned(
                right: 0,
                top: statsTop,
                child: _DockScrollArea(
                  maxExtent: upper - statsTop,
                  child: stats!,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomArea(double maxExtent, double bottomInset) {
    final stacked = <Widget>[];
    if (primaryPanel != null) stacked.add(primaryPanel!);
    for (final panel in panels) {
      if (stacked.isNotEmpty) stacked.add(SizedBox(height: panelGap));
      stacked.add(panel);
    }
    if (stacked.isEmpty && trailing == null) {
      return const AppNotificationBottomInset(child: SizedBox.shrink());
    }

    // Нижняя стопка сообщает свою высоту общему хосту уведомлений: SnackBar
    // всегда висит над кнопками карты и панелями, а не поверх них.
    return AppNotificationBottomInset(
      extraBottom: bottomInset,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxExtent),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: stacked.isEmpty
                    ? const SizedBox.shrink()
                    : _DockScrollArea(
                        maxExtent: maxExtent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: stacked,
                        ),
                      ),
              ),
              if (trailing != null) ...<Widget>[
                SizedBox(width: railGap),
                // Рейл тоже ограничен по высоте: на низком экране он
                // прокручивается, а не вылезает за пределы стопки.
                _DockScrollArea(maxExtent: maxExtent, child: trailing!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Прокручиваемая область оверлея с ограничением по высоте.
///
/// Пока содержимое помещается, прокрутка выключена ([NeverScrollableScrollPhysics]),
/// поэтому область не отбирает вертикальные жесты у карты и не рисует лишний
/// scrollbar. Когда содержимое перестаёт помещаться — включается штатная
/// прокрутка с общим scrollbar'ом приложения ([appScrollBehavior]) и отступом
/// справа, чтобы полоса не перекрывала содержимое.
class _DockScrollArea extends StatefulWidget {
  const _DockScrollArea({required this.maxExtent, required this.child});

  final double maxExtent;
  final Widget child;

  @override
  State<_DockScrollArea> createState() => _DockScrollAreaState();
}

class _DockScrollAreaState extends State<_DockScrollArea> {
  final ScrollController _controller = ScrollController();
  bool _scrollable = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant _DockScrollArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.positions.length != 1) return;
      final position = _controller.positions.first;
      if (!position.hasContentDimensions) return;
      _apply(position.maxScrollExtent > position.minScrollExtent);
    });
  }

  void _apply(bool next) {
    if (next == _scrollable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next == _scrollable) return;
      setState(() => _scrollable = next);
    });
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    _apply(notification.metrics.maxScrollExtent >
        notification.metrics.minScrollExtent);
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) {
      _apply(notification.metrics.maxScrollExtent >
          notification.metrics.minScrollExtent);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(0.0, widget.maxExtent)),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: appScrollBehavior,
            child: SingleChildScrollView(
              controller: _controller,
              primary: false,
              physics: _scrollable
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              padding: _scrollable
                  ? const EdgeInsets.only(right: 8)
                  : EdgeInsets.zero,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
