import 'package:flutter/material.dart';

const objectEditorColors = <Color>[
  Color(0xFFFF0000),
  Color(0xFF2196F3),
  Color(0xFF00A651),
  Color(0xFFFFEB3B),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFFFFFFFF),
];

/// Shared shell for object editors. The content stays local to each object,
/// while the sheet always exposes a drag affordance and safe scrolling.
class ObjectBottomSheet extends StatelessWidget {
  const ObjectBottomSheet({
    super.key,
    required this.child,
    this.backgroundColor,
    this.maxHeightFactor = 0.88,
  });

  final Widget child;
  final Color? backgroundColor;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: backgroundColor ?? theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ObjectEditorFields extends StatelessWidget {
  const ObjectEditorFields({
    super.key,
    required this.nameController,
    required this.descriptionController,
    required this.leading,
    this.trailing,
    this.colors = const <Color>[],
    this.selectedColor,
    this.onColorSelected,
    this.visible,
    this.onVisibilityChanged,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final Widget leading;
  final Widget? trailing;
  final List<Color> colors;
  final Color? selectedColor;
  final ValueChanged<Color>? onColorSelected;
  final bool? visible;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: nameController,
                style: TextStyle(color: foreground),
                decoration: const InputDecoration(
                  labelText: 'Название',
                  isDense: true,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descriptionController,
          minLines: 1,
          maxLines: 3,
          style: TextStyle(color: foreground),
          decoration: const InputDecoration(
            labelText: 'Описание',
            isDense: true,
          ),
        ),
        if (colors.isNotEmpty && onColorSelected != null) ...[
          const SizedBox(height: 14),
          Text('Цвет', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: colors.map((color) {
              final selected = color.toARGB32() == selectedColor?.toARGB32();
              return InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onColorSelected!(color),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : theme.dividerColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
        if (visible != null && onVisibilityChanged != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Видимость на карте'),
            value: visible!,
            onChanged: onVisibilityChanged,
          ),
      ],
    );
  }
}
