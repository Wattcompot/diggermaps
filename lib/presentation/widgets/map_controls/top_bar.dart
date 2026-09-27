import 'package:flutter/material.dart';

import '../../providers/map_search_controller.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.searchController,
    required this.onMenuPressed,
    required this.onLayersPressed,
  });

  final MapSearchController searchController;
  final VoidCallback onMenuPressed;
  final VoidCallback onLayersPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _MapIconButton(
          icon: Icons.menu,
          tooltip: 'Меню',
          onPressed: onMenuPressed,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(18),
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2D2D2D)
                : Colors.white.withValues(alpha: 0.96),
            clipBehavior: Clip.antiAlias,
            child: ListenableBuilder(
              listenable: searchController,
              builder: (context, _) => TextField(
                controller: searchController.textController,
                focusNode: searchController.searchFocusNode,
                onChanged: searchController.onSearchChanged,
                onTap: () {
                  if (searchController.textController.text.isEmpty) {
                    searchController.loadHistory();
                  } else {
                    searchController.showExistingResults();
                  }
                },
                style: const TextStyle(fontSize: 16, height: 1.2),
                decoration: InputDecoration(
                  hintText: 'Поиск места или координат',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  suffixIcon: searchController.textController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: searchController.clear,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: searchController.performSearch,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _MapIconButton(
          icon: Icons.layers_rounded,
          tooltip: 'Слои',
          onPressed: onLayersPressed,
        ),
      ],
    );
  }
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 2,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      );
}
