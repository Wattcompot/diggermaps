import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Управление поворотом карты по компасу.
///
/// При активации подписывается на heading устройства через Geolocator
/// и поворачивает карту. При повторном нажатии сбрасывает bearing в 0.
class MapCompassControl {
  bool _isActive = false;
  StreamSubscription<Position>? _headingSubscription;
  double _heading = 0;

  bool get isActive => _isActive;
  double get heading => _heading;

  void Function(double bearing)? onBearingChanged;
  VoidCallback? onStateChanged;

  Future<void> toggle() async {
    if (_isActive) {
      _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    _headingSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
      ),
    ).listen((position) {
      if (position.heading >= 0) {
        _heading = position.heading;
        onBearingChanged?.call(position.heading);
      }
    });

    _isActive = true;
    onStateChanged?.call();
  }

  void _stop() {
    _headingSubscription?.cancel();
    _headingSubscription = null;
    _isActive = false;
    _heading = 0;
    onBearingChanged?.call(0);
    onStateChanged?.call();
  }

  void dispose() {
    _stop();
  }
}

/// Виджет-кнопка компаса (красный круг с буквой N, поворачивается к северу).
class CompassRoseWidget extends StatelessWidget {
  final double bearing;

  const CompassRoseWidget({super.key, required this.bearing});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -bearing * math.pi / 180.0,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'N',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
