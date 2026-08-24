import 'package:flutter/material.dart';

import '../../providers/drawing_controller.dart';

class DrawingStatusBar extends StatelessWidget {
  const DrawingStatusBar({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final DrawingController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isActive) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.edit, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  controller.mode == MapDrawingMode.line
                      ? 'Режим: ${controller.modeLabel}'
                      : 'Режим: ${controller.modeLabel} | '
                          'Точек: ${controller.activePoints.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.white),
                onPressed: controller.undo,
              ),
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: 'Завершить',
                onPressed: onDone,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Очистить',
                onPressed: controller.clear,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Отмена',
                onPressed: controller.cancel,
              ),
            ],
          ),
        );
      },
    );
  }
}
