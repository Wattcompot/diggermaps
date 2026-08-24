import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/wikimapia_models.dart';

class WikimapiaObjectSheet extends StatelessWidget {
  const WikimapiaObjectSheet({super.key, required this.place});

  final WikimapiaPlace place;

  static Future<void> show(
    BuildContext context, {
    required WikimapiaPlace place,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WikimapiaObjectSheet(place: place),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comments = place.comments
        .where((comment) => comment.text.trim().isNotEmpty)
        .toList(growable: false);
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Material(
        color: const Color(0xFF2D2D2D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              place.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _LinkifiedDescription(
              place.description.trim().isEmpty
                  ? 'Описание отсутствует'
                  : place.description,
            ),
            const SizedBox(height: 12),
            if (comments.isNotEmpty) ...<Widget>[
              const Text(
                'Комментарии',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...comments.map(
                (comment) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: comment.author.trim().isEmpty
                              ? ''
                              : '${comment.author}: ',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: comment.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...<Widget>[
              const Text(
                'Комментариев нет',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            if (place.categories.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: place.categories
                    .map(
                      (category) => Chip(
                        label: Text(
                          category.title,
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: Colors.blue.shade300,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(growable: false),
              ),
            if (place.photos.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: place.photos.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        place.photos[index].thumbnail,
                        width: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkifiedDescription extends StatelessWidget {
  const _LinkifiedDescription(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final urlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in urlPattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(url)),
            child: Text(
              url,
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) {
      spans.add(TextSpan(text: text.substring(offset)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(color: Colors.white),
    );
  }
}
