import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/track.dart';
import '../../data/utils/measurement_utils.dart';

class TrackRecordingController extends ChangeNotifier {
  TrackRecordingController({required this.ensureLocationPermission});

  final Future<bool> Function() ensureLocationPermission;

  bool _isRecordingTrack = false;
  bool _isTrackPaused = false;
  bool _skipNextTrackDistance = false;
  final List<LatLng> _activeTrackPoints = <LatLng>[];
  final List<TrackSegment> _activeTrackSegments = <TrackSegment>[];
  StreamSubscription<Position>? _locationSubscription;
  Timer? _trackTimer;
  DateTime? _trackStartTime;
  DateTime? _trackSegmentStartedAt;
  double _trackSegmentStartDistance = 0;
  double _trackDistance = 0;
  double _currentSpeed = 0;

  bool get isRecording => _isRecordingTrack;
  bool get isPaused => _isTrackPaused;
  List<LatLng> get activePoints =>
      List<LatLng>.unmodifiable(_activeTrackPoints);
  List<TrackSegment> get activeSegments =>
      List<TrackSegment>.unmodifiable(_activeTrackSegments);
  double get distance => _trackDistance;
  double get currentSpeed => _currentSpeed;
  DateTime? get startedAt => _trackStartTime;

  Future<bool> start() async {
    if (_isRecordingTrack || !await ensureLocationPermission()) return false;

    final startedAt = DateTime.now();
    _isRecordingTrack = true;
    _isTrackPaused = false;
    _skipNextTrackDistance = false;
    _activeTrackPoints.clear();
    _activeTrackSegments.clear();
    _trackStartTime = startedAt;
    _trackSegmentStartedAt = startedAt;
    _trackSegmentStartDistance = 0;
    _trackDistance = 0;
    _currentSpeed = 0;
    notifyListeners();

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DiggerMaps',
          notificationText: 'Запись трека...',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen(_onPosition);
    _startTimer();
    return true;
  }

  void _onPosition(Position position) {
    if (_isTrackPaused) return;
    final point = LatLng(position.latitude, position.longitude);
    if (_activeTrackPoints.isNotEmpty && !_skipNextTrackDistance) {
      _trackDistance += MeasurementUtils.calculateDistance(
        _activeTrackPoints.last,
        point,
      );
    }
    _skipNextTrackDistance = false;
    _activeTrackPoints.add(point);
    _currentSpeed = position.speed * 3.6;
    notifyListeners();
  }

  void _startTimer() {
    _trackTimer?.cancel();
    _trackTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => notifyListeners(),
    );
  }

  void togglePause() {
    if (!_isRecordingTrack) return;
    final now = DateTime.now();
    _finishCurrentSegment(now);
    _isTrackPaused = !_isTrackPaused;
    _trackSegmentStartedAt = now;
    _trackSegmentStartDistance = _trackDistance;
    if (_isTrackPaused) {
      _currentSpeed = 0;
      _trackTimer?.cancel();
      _trackTimer = null;
    } else {
      _skipNextTrackDistance = true;
      _startTimer();
    }
    notifyListeners();
  }

  Future<Track?> stop() async {
    if (!_isRecordingTrack) return null;
    final stoppedAt = DateTime.now();
    _finishCurrentSegment(stoppedAt);
    final points = List<LatLng>.from(_activeTrackPoints);
    final segments = List<TrackSegment>.from(_activeTrackSegments);
    final distance = _trackDistance;
    final startedAt = _trackStartTime ?? stoppedAt;
    final duration = segments
        .where((segment) => !segment.isPause)
        .fold<int>(0, (sum, segment) => sum + segment.duration.inSeconds);
    await _stopLocationUpdates();

    final track = points.length < 2
        ? null
        : Track(
            name: '',
            points: points,
            distance: distance,
            duration: duration,
            visible: true,
            segments: segments,
            createdAt: startedAt,
          );
    _reset();
    return track;
  }

  Future<void> cancel() async {
    await _stopLocationUpdates();
    _reset();
  }

  void _finishCurrentSegment(DateTime endedAt) {
    final startedAt = _trackSegmentStartedAt;
    if (startedAt == null || endedAt.isBefore(startedAt)) return;
    _activeTrackSegments.add(
      TrackSegment(
        type: _isTrackPaused ? 'pause' : 'recording',
        startedAt: startedAt,
        endedAt: endedAt,
        distance:
            _isTrackPaused ? 0 : _trackDistance - _trackSegmentStartDistance,
      ),
    );
  }

  Future<void> _stopLocationUpdates() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _trackTimer?.cancel();
    _trackTimer = null;
  }

  void _reset() {
    _isRecordingTrack = false;
    _isTrackPaused = false;
    _skipNextTrackDistance = false;
    _activeTrackPoints.clear();
    _activeTrackSegments.clear();
    _trackStartTime = null;
    _trackSegmentStartedAt = null;
    _trackSegmentStartDistance = 0;
    _trackDistance = 0;
    _currentSpeed = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _trackTimer?.cancel();
    super.dispose();
  }
}
