import 'dart:convert';
import 'package:latlong2/latlong.dart';

class TrackSegment {
  const TrackSegment({
    required this.type,
    required this.startedAt,
    required this.endedAt,
    this.distance = 0,
  });

  final String type;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distance;

  bool get isPause => type == 'pause';
  Duration get duration => endedAt.difference(startedAt);

  Map<String, dynamic> toMap() => {
        'type': type,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'distance': distance,
      };

  factory TrackSegment.fromMap(Map<String, dynamic> map) => TrackSegment(
        type: map['type'] as String? ?? 'recording',
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        distance: (map['distance'] as num? ?? 0).toDouble(),
      );
}

class Track {
  final int? id;
  final String name;
  final String? description;
  final List<LatLng> points;
  final double distance; // в метрах
  final int duration; // в секундах
  final int color;
  final bool visible;
  final List<TrackSegment> segments;
  final DateTime createdAt;

  Track({
    this.id,
    required this.name,
    this.description,
    required this.points,
    required this.distance,
    required this.duration,
    this.color = 0xFFFF0000,
    this.visible = false,
    this.segments = const <TrackSegment>[],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Track copyWith({
    int? id,
    String? name,
    String? description,
    List<LatLng>? points,
    double? distance,
    int? duration,
    int? color,
    bool? visible,
    List<TrackSegment>? segments,
    DateTime? createdAt,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      points: points ?? this.points,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      color: color ?? this.color,
      visible: visible ?? this.visible,
      segments: segments ?? this.segments,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'points_json': jsonEncode(
        points.map((p) => [p.latitude, p.longitude]).toList(),
      ),
      'distance': distance,
      'duration': duration,
      'color': color,
      'visible': visible ? 1 : 0,
      'segments_json': jsonEncode(
        segments.map((segment) => segment.toMap()).toList(growable: false),
      ),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    final List<dynamic> decoded = jsonDecode(map['points_json'] as String);
    final segmentsJson = map['segments_json'] as String?;
    final decodedSegments = segmentsJson == null || segmentsJson.isEmpty
        ? const <dynamic>[]
        : jsonDecode(segmentsJson) as List<dynamic>;
    return Track(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      points: decoded.map((p) {
        final List<dynamic> coords = p as List<dynamic>;
        return LatLng(
          (coords[0] as num).toDouble(),
          (coords[1] as num).toDouble(),
        );
      }).toList(),
      distance: (map['distance'] as num).toDouble(),
      duration: map['duration'] as int,
      color: (map['color'] as num?)?.toInt() ?? 0xFFFF0000,
      visible: (map['visible'] as num? ?? 0) != 0,
      segments: decodedSegments
          .map((segment) => TrackSegment.fromMap(
                Map<String, dynamic>.from(segment as Map),
              ))
          .toList(growable: false),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
