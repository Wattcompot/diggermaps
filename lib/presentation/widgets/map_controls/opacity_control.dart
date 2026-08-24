import 'package:flutter/material.dart';

import '../../providers/map_layers_controller.dart';

class OpacityControl extends StatelessWidget {
  const OpacityControl({
    super.key,
    required this.controller,
    this.onImportedLayerSelected,
  });

  final MapLayersController controller;
  final ValueChanged<int>? onImportedLayerSelected;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final layers = controller.activeOpacityLayers;
        final active = controller.selectedOpacityLayer;
        if (active == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final panelColor = theme.brightness == Brightness.dark
            ? const Color(0xCC1E1E1E)
            : theme.colorScheme.surface.withValues(alpha: 0.96);
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              PopupMenuButton<String>(
                tooltip: 'Выбрать карту',
                offset: const Offset(-24, 44),
                onOpened: () => controller.setOpacitySelectorOpen(true),
                onCanceled: () => controller.setOpacitySelectorOpen(false),
                onSelected: (key) {
                  controller.selectOpacityLayer(key);
                  final selected = layers.firstWhere((item) => item.key == key);
                  final id = selected.importedMap?.id;
                  if (id != null) onImportedLayerSelected?.call(id);
                },
                itemBuilder: (_) => _items(layers),
                child: SizedBox(
                  width: 96,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.map_outlined, size: 18),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _shortName(active.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AnimatedRotation(
                        turns: controller.opacitySelectorOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.keyboard_arrow_down, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Slider(
                  value: active.opacity.clamp(0, 1),
                  min: 0,
                  max: 1,
                  divisions: 100,
                  activeColor: const Color(0xFFA67B5B),
                  inactiveColor: Colors.grey,
                  onChanged: (value) => controller.updateOpacity(active, value),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${(active.opacity * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _items(List<OpacityLayerSelection> layers) {
    final imported =
        layers.where((layer) => layer.kind == OpacityLayerKind.imported);
    final catalog =
        layers.where((layer) => layer.kind == OpacityLayerKind.catalog);
    return <PopupMenuEntry<String>>[
      if (imported.isNotEmpty) ...<PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text('Импортированные'),
        ),
        ...imported.map(
          (layer) => PopupMenuItem<String>(
            value: layer.key,
            child: Text(layer.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      if (catalog.isNotEmpty) ...<PopupMenuEntry<String>>[
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text('Каталог'),
        ),
        ...catalog.map(
          (layer) => PopupMenuItem<String>(
            value: layer.key,
            child: Text(layer.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    ];
  }

  String _shortName(String value) {
    final name = value.trim();
    return name.length <= 10 ? name : '${name.substring(0, 9)}…';
  }
}
