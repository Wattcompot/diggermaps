import 'package:flutter/material.dart';

import '../../providers/drawing_controller.dart';
import '../object_bottom_sheet.dart' show objectEditorColors;

/// Компактная панель статуса рисования.
///
/// * undo оставлен, дублирующая «очистить» (trash) убрана для всех режимов —
///   отмена режима делается кнопкой close.
/// * во время создания доступны стиль (палитра) и толщина линии, которые
///   сразу отражаются в текущем renderer'е и попадут в сохраняемый объект.
/// * появление/скрытие и смена счётчика анимированы штатными виджетами
///   (без сторонних пакетов).
class DrawingStatusBar extends StatefulWidget {
  const DrawingStatusBar({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final DrawingController controller;
  final VoidCallback onDone;

  @override
  State<DrawingStatusBar> createState() => _DrawingStatusBarState();
}

class _DrawingStatusBarState extends State<DrawingStatusBar> {
  bool _styleExpanded = false;

  @override
  void didUpdateWidget(covariant DrawingStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controller.isActive) _styleExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
          child: widget.controller.isActive
              ? _panel(context)
              : const SizedBox.shrink(key: ValueKey<String>('drawing-idle')),
        );
      },
    );
  }

  Widget _panel(BuildContext context) {
    final controller = widget.controller;
    return Container(
      key: const ValueKey<String>('drawing-panel'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.edit, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    _statusText(controller),
                    key: ValueKey<String>(_statusText(controller)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.white),
                tooltip: 'Отменить точку',
                onPressed: controller.undo,
              ),
              IconButton(
                icon: Icon(
                  Icons.palette_outlined,
                  color: _styleExpanded ? Colors.amber : Colors.white,
                ),
                tooltip: 'Стиль',
                onPressed: () =>
                    setState(() => _styleExpanded = !_styleExpanded),
              ),
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: 'Завершить',
                onPressed: widget.onDone,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Отмена',
                onPressed: controller.cancel,
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _styleExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _styleControls(controller),
          ),
        ],
      ),
    );
  }

  String _statusText(DrawingController controller) =>
      'Режим: ${controller.modeLabel} | Точек: ${controller.activePoints.length}';

  Widget _styleControls(DrawingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: objectEditorColors.map((color) {
              final selected = color.toARGB32() == controller.color.toARGB32();
              return InkWell(
                customBorder: const CircleBorder(),
                onTap: () => controller.setColor(color),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
          Row(
            children: <Widget>[
              const Icon(Icons.line_weight, color: Colors.white70, size: 16),
              Expanded(
                child: Slider(
                  value: controller.strokeWidth.clamp(
                    DrawingController.minStrokeWidth,
                    DrawingController.maxStrokeWidth,
                  ),
                  min: DrawingController.minStrokeWidth,
                  max: DrawingController.maxStrokeWidth,
                  divisions: 22,
                  activeColor: controller.color,
                  onChanged: controller.setStrokeWidth,
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  controller.strokeWidth.toStringAsFixed(0),
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
