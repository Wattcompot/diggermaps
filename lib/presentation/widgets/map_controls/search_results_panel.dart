import 'package:flutter/material.dart';

import '../../providers/map_search_controller.dart';
import '../../../data/repositories/search_repository.dart';

class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({
    super.key,
    required this.controller,
    required this.onSelected,
  });

  final MapSearchController controller;
  final ValueChanged<SearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: controller.panelVisible
            ? Card(
                key: const ValueKey('search-results-visible'),
                margin: const EdgeInsets.only(top: 4),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: controller.loading
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : controller.noResults
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: Text('Ничего не найдено')),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: controller.results.length,
                              itemBuilder: (context, index) {
                                final result = controller.results[index];
                                return ListTile(
                                  title: Text(result.title),
                                  subtitle: Text(result.subtitle),
                                  onTap: () => onSelected(result),
                                );
                              },
                            ),
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey('search-results-hidden'),
              ),
      ),
    );
  }
}
