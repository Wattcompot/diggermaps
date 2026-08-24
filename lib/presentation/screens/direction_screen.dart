import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

class DirectionScreen extends StatefulWidget {
  const DirectionScreen({
    super.key,
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  @override
  State<DirectionScreen> createState() => _DirectionScreenState();
}

class _DirectionScreenState extends State<DirectionScreen> {
  static const _accentColor = Color(0xFFA67B5B);
  static const _backgroundColor = Color(0xFF121212);
  static const _panelColor = Color(0xFF1E1E1E);

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Position? _position;
  double _heading = 0;
  String? _statusMessage;
  bool _permissionMissing = false;
  bool _voiceNotifications = false;

  @override
  void initState() {
    super.initState();
    _startCompass();
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSubscription = events.listen((event) {
      final heading = event.heading;
      if (!mounted || heading == null) return;
      setState(() => _heading = (heading + 360) % 360);
    });
  }

  Future<void> _initializeLocation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'GPS выключен. Включите геолокацию.';
        _permissionMissing = false;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = 'Нет разрешения на геолокацию';
        _permissionMissing = true;
      });
      return;
    }

    setState(() {
      _statusMessage = null;
      _permissionMissing = false;
    });

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() => _position = position);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Не удалось получить геопозицию');
      },
    );

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      if (!mounted) return;
      setState(() => _position = position);
    } catch (_) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Не удалось получить геопозицию');
    }
  }

  Future<void> _requestPermission() async {
    final permission = await Geolocator.requestPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = 'Нет разрешения на геолокацию';
        _permissionMissing = true;
      });
      return;
    }
    await _initializeLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _panelColor,
        foregroundColor: Colors.white,
        title: const Text('Направление на точку'),
      ),
      body: _statusMessage != null
          ? _buildStatus()
          : _position == null
              ? const Center(child: CircularProgressIndicator())
              : _buildDirectionContent(_position!),
    );
  }

  Widget _buildStatus() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 20),
            if (_permissionMissing)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _requestPermission,
                child: const Text('Запросить разрешение'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _initializeLocation,
                child: const Text('Повторить'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionContent(Position position) {
    final distance = _distanceToTarget(position);
    final bearing = _bearingToTarget(position);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compassSize = math.min(constraints.maxWidth - 32, 340.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.location_on,
                        label: 'РАССТОЯНИЕ',
                        value: _formatDistance(distance),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.gps_fixed,
                        label: 'ТОЧНОСТЬ',
                        value: '${position.accuracy.toStringAsFixed(0)} м',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InfoCard(
                        icon: Icons.terrain,
                        label: 'ВЫСОТА',
                        value: '${position.altitude.toStringAsFixed(0)} м',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '${bearing.round()}°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox.square(
                  dimension: compassSize,
                  child: CustomPaint(
                    painter: _DirectionCompassPainter(
                      heading: _heading,
                      targetBearing: bearing,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CompassLegendItem(
                      icon: Icons.location_on,
                      color: Colors.red,
                      label: 'Метка',
                    ),
                    SizedBox(width: 24),
                    _CompassLegendItem(
                      icon: Icons.navigation,
                      color: Colors.blue,
                      label: 'Север',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  tileColor: _panelColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: const Text(
                    'Голосовые уведомления',
                    style: TextStyle(color: Colors.white),
                  ),
                  secondary: const Icon(Icons.volume_up, color: Colors.white),
                  value: _voiceNotifications,
                  activeThumbColor: _accentColor,
                  activeTrackColor: _accentColor.withValues(alpha: 0.5),
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _voiceNotifications = value);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _distanceToTarget(Position position) {
    const earthRadius = 6371000.0;
    final lat1 = _radians(position.latitude);
    final lat2 = _radians(widget.lat);
    final deltaLat = _radians(widget.lat - position.latitude);
    final deltaLng = _radians(widget.lng - position.longitude);
    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _bearingToTarget(Position position) {
    final lat1 = _radians(position.latitude);
    final lat2 = _radians(widget.lat);
    final deltaLng = _radians(widget.lng - position.longitude);
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return (_degrees(math.atan2(y, x)) + 360) % 360;
  }

  double _radians(double degrees) => degrees * math.pi / 180;
  double _degrees(double radians) => radians * 180 / math.pi;

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} м';
    return '${(meters / 1000).toStringAsFixed(2)} км';
  }
}

class _CompassLegendItem extends StatelessWidget {
  const _CompassLegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _DirectionScreenState._panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: _DirectionScreenState._panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionCompassPainter extends CustomPainter {
  const _DirectionCompassPainter({
    required this.heading,
    required this.targetBearing,
  });

  final double heading;
  final double targetBearing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 20;
    final ringPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ringPaint);

    for (var degree = 0; degree < 360; degree += 30) {
      final angle = _radians(degree - 90);
      final major = degree % 90 == 0;
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final innerRadius = radius - (major ? 16 : 9);
      final inner = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = major ? Colors.white : Colors.white54
          ..strokeWidth = major ? 2 : 1,
      );
    }

    _drawLabel(canvas, center, radius - 31, 0, '0/360');
    _drawLabel(canvas, center, radius - 27, 90, '90');
    _drawLabel(canvas, center, radius - 27, 180, '180');
    _drawLabel(canvas, center, radius - 27, 270, '270');

    _drawArrow(
      canvas,
      center,
      -heading,
      Colors.blue,
      radius * 0.62,
      label: 'N',
    );
    _drawArrow(
      canvas,
      center,
      targetBearing - heading,
      Colors.red,
      radius * 0.78,
      icon: Icons.location_on,
    );

    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF1E1E1E));
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double degree,
    String text,
  ) {
    final angle = _radians(degree - 90);
    final position = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawArrow(
    Canvas canvas,
    Offset center,
    double degree,
    Color color,
    double length, {
    String? label,
    IconData? icon,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_radians(degree));
    final needle = Path()
      ..moveTo(0, -length)
      ..lineTo(-11, length * 0.14)
      ..lineTo(0, length * 0.04)
      ..lineTo(11, length * 0.14)
      ..close();
    canvas.drawPath(needle, Paint()..color = color);
    canvas.drawPath(
      needle,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (label != null) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(-labelPainter.width / 2, -length - 26),
      );
    }
    if (icon != null) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset(-iconPainter.width / 2, -length - 34),
      );
    }
    canvas.restore();
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(covariant _DirectionCompassPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.targetBearing != targetBearing;
  }
}
