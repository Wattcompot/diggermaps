import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Масштабная линейка, динамически пересчитываемая при зуме карты.
///
/// Использует широту центра карты для расчёта реального расстояния на один
/// пиксель экрана в метрах. Показывает «круглую» длину (100м, 200м, 500м, 1км, ...)
/// и подбирает подходящую единицу измерения.
class MapScaleBar extends StatelessWidget {
  final MapCamera camera;
  final double maxWidth;
  final bool metric;

  const MapScaleBar({
    super.key,
    required this.camera,
    this.maxWidth = 200,
    this.metric = true,
  });

  @override
  Widget build(BuildContext context) {
    final scaleData = _computeScale();

    if (scaleData.pixels < 40) {
      return const SizedBox(width: 0, height: 24);
    }

    final label = _formatLabel(scaleData.distanceMeters);
    final barWidth = scaleData.pixels.clamp(40.0, maxWidth);
    final foreground = Theme.of(context).iconTheme.color ?? Colors.black87;

    return SizedBox(
      width: barWidth + 8,
      height: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                width: barWidth,
                height: 3,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: foreground, width: 2),
                    right: BorderSide(color: foreground, width: 2),
                    bottom: BorderSide(color: foreground, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _ScaleData _computeScale() {
    // Метров на пиксель на экваторе при текущем зуме
    final equatorMetersPerPixel = 156543.03392 *
        math.cos(camera.center.latitude * math.pi / 180.0) /
        math.pow(2.0, camera.zoom);

    // Подбираем «круглую» длину для отображения
    final niceDistances = metric
        ? [
            1,
            2,
            5,
            10,
            20,
            50,
            100,
            200,
            500,
            1000,
            2000,
            5000,
            10000,
            20000,
            50000,
            100000,
            200000,
            500000
          ]
        : [
            1,
            2,
            5,
            10,
            20,
            50,
            100,
            200,
            500,
            1000,
            2000,
            5280,
            10560,
            26400,
            52800
          ];

    for (final dist in niceDistances) {
      final pixels = dist / equatorMetersPerPixel;
      if (pixels >= 60 && pixels <= maxWidth) {
        return _ScaleData(
            distanceMeters: metric ? dist.toDouble() : dist * 0.3048, // ft → m
            pixels: pixels);
      }
    }

    // Fallback
    return _ScaleData(distanceMeters: equatorMetersPerPixel * 100, pixels: 100);
  }

  String _formatLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} км';
    }
    return '${meters.round()} м';
  }
}

class _ScaleData {
  final double distanceMeters;
  final double pixels;
  const _ScaleData({required this.distanceMeters, required this.pixels});
}
