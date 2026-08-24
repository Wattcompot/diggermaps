import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationController extends ChangeNotifier {
  LocationController({
    required MapController mapController,
    required ValueChanged<String> onMessage,
  })  : _mapController = mapController,
        _onMessage = onMessage;

  final MapController _mapController;
  final ValueChanged<String> _onMessage;

  bool _followLocation = false;
  bool _locationLayerEnabled = false;

  bool get followLocation => _followLocation;
  bool get locationLayerEnabled => _locationLayerEnabled;

  Future<void> centerOnLocation() async {
    if (_followLocation) return;
    if (!await handleLocationPermission()) return;
    await _moveToCurrentLocation(follow: true);
  }

  Future<void> centerOnceOnLocation() async {
    if (!await handleLocationPermission()) return;
    await _moveToCurrentLocation(follow: false);
  }

  Future<void> centerOnStartup() async {
    if (!await handleLocationPermission()) return;
    try {
      final position = await _currentPosition();
      _locationLayerEnabled = true;
      notifyListeners();
      _mapController.move(LatLng(position.latitude, position.longitude), 17);
    } catch (_) {
      _onMessage('Включите геолокацию');
    }
  }

  void stopFollowLocation() {
    if (!_followLocation) return;
    _followLocation = false;
    notifyListeners();
  }

  Future<bool> handleLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _onMessage('Геолокация отключена');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _onMessage('Нет разрешения на геолокацию');
      return false;
    }
    return true;
  }

  Future<void> _moveToCurrentLocation({required bool follow}) async {
    try {
      final position = await _currentPosition();
      _locationLayerEnabled = true;
      _followLocation = follow;
      notifyListeners();
      _mapController.move(LatLng(position.latitude, position.longitude), 17);
    } catch (_) {
      _onMessage('Включите геолокацию');
    }
  }

  Future<Position> _currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
}
