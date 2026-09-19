import 'package:flutter/material.dart';

import 'marker_builder.dart';
import 'marker_shape.dart';

class MarkerAppearanceButton extends StatelessWidget {
  const MarkerAppearanceButton(
      {super.key,
      required this.shape,
      required this.colorHex,
      required this.onTap});
  final String shape;
  final String colorHex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Изменить внешний вид',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(children: <Widget>[
              Center(
                  child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: MarkerShape(
                    key: ValueKey('$shape:$colorHex'),
                    shape: shape,
                    color: MarkerBuilder.parseColorHex(colorHex),
                    size: 36),
              )),
              const Positioned(
                  right: 5,
                  bottom: 5,
                  child: Icon(Icons.edit_outlined, size: 15)),
            ]),
          ),
        ),
      );
}
