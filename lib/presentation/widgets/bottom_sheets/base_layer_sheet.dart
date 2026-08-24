import 'package:flutter/material.dart';

import '../../../data/repositories/custom_map_repository.dart';

class BaseLayerSheet extends StatefulWidget {
  const BaseLayerSheet({
    super.key,
    required this.defaultSources,
    required this.currentLayerId,
    required this.onLayerChanged,
    required this.currentZoom,
    required this.onZoomClamp,
  });

  final List<CustomMapLayer> defaultSources;
  final String currentLayerId;
  final ValueChanged<String> onLayerChanged;
  final double currentZoom;
  final VoidCallback onZoomClamp;

  static Future<void> show(
    BuildContext context, {
    required List<CustomMapLayer> defaultSources,
    required String currentLayerId,
    required ValueChanged<String> onLayerChanged,
    required double currentZoom,
    required VoidCallback onZoomClamp,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BaseLayerSheet(
        defaultSources: defaultSources,
        currentLayerId: currentLayerId,
        onLayerChanged: onLayerChanged,
        currentZoom: currentZoom,
        onZoomClamp: onZoomClamp,
      ),
    );
  }

  @override
  State<BaseLayerSheet> createState() => _BaseLayerSheetState();
}

class _BaseLayerSheetState extends State<BaseLayerSheet> {
  late String _currentLayerId;

  @override
  void initState() {
    super.initState();
    _currentLayerId = widget.currentLayerId;
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.defaultSources
        .where((layer) => layer.type == MapLayerType.base)
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Слои карты',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: RadioGroup<String>(
                groupValue: _currentLayerId,
                onChanged: (value) {
                  if (value == null) return;
                  final layer = sources.firstWhere((item) => item.id == value);
                  setState(() => _currentLayerId = value);
                  widget.onLayerChanged(value);
                  if (widget.currentZoom > layer.maxZoom) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => widget.onZoomClamp(),
                    );
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: sources
                      .map(
                        (layer) => RadioListTile<String>(
                          value: layer.id,
                          secondary: const Icon(Icons.map_rounded),
                          title: Text(layer.name),
                          subtitle: Text('Макс. масштаб: ${layer.maxZoom}'),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
