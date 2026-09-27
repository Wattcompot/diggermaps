import 'package:flutter/material.dart';

import 'marker_builder.dart';
import 'marker_shape.dart';

class MarkerAppearanceButton extends StatelessWidget {
  const MarkerAppearanceButton(
      {super.key,
      required this.shape,
      required this.colorHex,
      required this.size,
      required this.onTap});

  final String shape;
  final String colorHex;

  /// Размер глифа метки — приходит от единственного состояния размера
  /// (метка при редактировании, выбор в пикере при создании). Отдельного
  /// управления размером у кнопки нет.
  final double size;

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
                // Размер анимируем, форму/цвет — кроссфейдом, поэтому при
                // смене размера глиф плавно растёт/уменьшается, а при смене
                // формы или цвета мягко переключается.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: size, end: size),
                  duration: kMarkerAnimationDuration,
                  curve: Curves.easeOut,
                  builder: (context, animatedSize, _) => AnimatedSwitcher(
                    duration: kMarkerAnimationDuration,
                    child: MarkerShape(
                        key: ValueKey('$shape:$colorHex'),
                        shape: shape,
                        color: MarkerBuilder.parseColorHex(colorHex),
                        size: animatedSize),
                  ),
                ),
              ),
              const Positioned(
                  right: 5,
                  bottom: 5,
                  child: Icon(Icons.edit_outlined, size: 15)),
            ]),
          ),
        ),
      );
}
