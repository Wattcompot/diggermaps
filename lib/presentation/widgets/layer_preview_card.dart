import 'package:flutter/material.dart';

/// Карточка с превью тайла для выбора базового слоя карты.
///
/// Загружает тайл из URL-шаблона для центральной точки карты на зуме 5-6
/// и отображает его как превью.
class LayerPreviewCard extends StatelessWidget {
  final String layerId;
  final String name;
  final String urlTemplate;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;

  const LayerPreviewCard({
    super.key,
    required this.layerId,
    required this.name,
    required this.urlTemplate,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // Вычисляем URL тайла для центра Москвы на зуме 5 (хороший обзор)
    const previewZoom = 5;

    // OSM tile X from longitude
    final tileX = ((37.6184 + 180) / 360 * (1 << previewZoom)).floor();

    // OSM tile Y from latitude
    const latRad = 55.7512 * 3.141592653589793 / 180;
    final tileY = ((1.0 -
                0.5 *
                    (1.0 +
                        (1 /
                            3.141592653589793 *
                            (2 *
                                (3.141592653589793 -
                                    2 * 3.141592653589793 * latRad))))) *
            (1 << previewZoom))
        .floor();

    final previewUrl = urlTemplate
        .replaceAll('{z}', '$previewZoom')
        .replaceAll('{x}', '$tileX')
        .replaceAll('{y}', '$tileY')
        .replaceAll('{s}', 'a') // subdomain fallback
        .replaceAll('{r}', ''); // retina fallback

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF8E5C2A) : Colors.transparent,
            width: isSelected ? 2.5 : 0,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Image.network(
                previewUrl,
                width: 160,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 160,
                  height: 100,
                  color: Colors.grey[300],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          color: Colors.grey[600], size: 32),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8E5C2A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
