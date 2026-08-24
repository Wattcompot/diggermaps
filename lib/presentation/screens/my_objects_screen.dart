import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/map_layers.dart';
import '../../data/models/drawing.dart';
import '../../data/models/track.dart';
import '../../data/models/user_marker.dart';
import '../providers/map_data_controller.dart';
import '../widgets/confirm_object_delete.dart';

enum MapObjectType { marker, drawing, track }

class MapObjectTarget {
  const MapObjectTarget({
    required this.type,
    required this.id,
  });

  final MapObjectType type;
  final int id;
}

class MyObjectsScreen extends StatefulWidget {
  const MyObjectsScreen({
    super.key,
    required this.dataController,
  });

  final MapDataController dataController;

  @override
  State<MyObjectsScreen> createState() => _MyObjectsScreenState();
}

class _MyObjectsScreenState extends State<MyObjectsScreen> {
  static const _accentColor = Color(0xFFA67B5B);
  static const _panelColor = Color(0xFF2D2D2D);

  late final TextEditingController _markerSearchController;
  late final TextEditingController _drawingSearchController;
  late final TextEditingController _trackSearchController;

  List<UserMarker> _markers = const [];
  List<Drawing> _drawings = const [];
  List<Track> _tracks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _markerSearchController = TextEditingController();
    _drawingSearchController = TextEditingController();
    _trackSearchController = TextEditingController();
    _loadObjects();
  }

  @override
  void dispose() {
    _markerSearchController.dispose();
    _drawingSearchController.dispose();
    _trackSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadObjects() async {
    await Future.wait([
      widget.dataController.loadUserMarkers(),
      widget.dataController.loadDrawings(),
      widget.dataController.loadTracks(),
    ]);
    if (!mounted) return;
    setState(() {
      _markers = widget.dataController.myMarkers;
      _drawings = widget.dataController.myDrawings;
      _tracks = widget.dataController.myTracks;
      _loading = false;
    });
  }

  void _showOnMap(MapObjectType type, int? id) {
    if (id == null) return;
    Navigator.of(context).pop(MapObjectTarget(type: type, id: id));
  }

  Future<void> _setMarkerVisibility(UserMarker marker, bool visible) async {
    final updated = marker.copyWith(visible: visible);
    await widget.dataController.updateMarker(updated);
    if (!mounted) return;
    final items = List<UserMarker>.from(_markers);
    final index = items.indexWhere((item) => item.id == marker.id);
    if (index >= 0) items[index] = updated;
    setState(() => _markers = items);
  }

  Future<void> _setDrawingVisibility(Drawing drawing, bool visible) async {
    final updated = drawing.copyWith(visible: visible);
    await widget.dataController.updateDrawing(updated);
    if (!mounted) return;
    final items = List<Drawing>.from(_drawings);
    final index = items.indexWhere((item) => item.id == drawing.id);
    if (index >= 0) items[index] = updated;
    setState(() => _drawings = items);
  }

  Future<void> _deleteMarker(UserMarker marker) async {
    final id = marker.id;
    if (id == null) return;
    if (!await confirmObjectDelete(
      context,
      type: 'метку',
      name: marker.name,
    )) {
      return;
    }
    await widget.dataController.deleteMarker(id);
    if (!mounted) return;
    setState(() {
      _markers = _markers.where((item) => item.id != id).toList();
    });
  }

  Future<void> _deleteDrawing(Drawing drawing) async {
    final id = drawing.id;
    if (id == null) return;
    if (!await confirmObjectDelete(
      context,
      type: drawing.category != 'measurement'
          ? 'рисунок'
          : drawing.type == 'line'
              ? 'линейку'
              : 'измерение',
      name: drawing.name,
    )) {
      return;
    }
    await widget.dataController.deleteDrawing(id);
    if (!mounted) return;
    setState(() {
      _drawings = _drawings.where((item) => item.id != id).toList();
    });
  }

  Future<void> _setTrackVisibility(Track track, bool visible) async {
    final updated = track.copyWith(visible: visible);
    await widget.dataController.updateTrack(updated);
    if (!mounted) return;
    final items = List<Track>.from(_tracks);
    final index = items.indexWhere((item) => item.id == track.id);
    if (index >= 0) items[index] = updated;
    setState(() => _tracks = items);
  }

  Future<void> _deleteTrack(Track track) async {
    final id = track.id;
    if (id == null) return;
    if (!await confirmObjectDelete(
      context,
      type: 'трек',
      name: track.name,
    )) {
      return;
    }
    await widget.dataController.deleteTrack(id);
    if (!mounted) return;
    setState(() {
      _tracks = _tracks.where((item) => item.id != id).toList();
    });
  }

  Future<void> _shareMarker(UserMarker marker) async {
    final description = marker.description?.trim();
    final text = StringBuffer()
      ..writeln(marker.name)
      ..writeln('${marker.lat}, ${marker.lng}');
    if (description != null && description.isNotEmpty) {
      text.writeln(description);
    }
    await Share.share(text.toString());
  }

  Future<void> _shareDrawing(Drawing drawing) async {
    final points = drawing.points
        .map((point) => '${point.latitude}, ${point.longitude}')
        .join('\n');
    await Share.share('${drawing.name}\n$points');
  }

  Future<void> _shareTrack(Track track) async {
    final averageSpeed =
        track.duration <= 0 ? 0.0 : track.distance / track.duration * 3.6;
    await Share.share(
      '${track.name}\n'
      '${(track.distance / 1000).toStringAsFixed(2)} км, '
      'средняя скорость ${averageSpeed.toStringAsFixed(1)} км/ч',
    );
  }

  String _formatCreatedAt(DateTime createdAt) {
    return DateFormat('dd.MM.yyyy, HH:mm').format(createdAt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _panelColor,
          foregroundColor: Colors.white,
          title: const Text('Мои объекты'),
          bottom: const TabBar(
            indicatorColor: _accentColor,
            labelColor: _accentColor,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.location_pin), text: 'Метки'),
              Tab(icon: Icon(Icons.show_chart), text: 'Рисунки'),
              Tab(icon: Icon(Icons.route), text: 'Треки'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildMarkersTab(),
                  _buildDrawingsTab(),
                  _buildTracksTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildMarkersTab() {
    final query = _markerSearchController.text.trim().toLowerCase();
    final items = _markers
        .where((marker) => marker.name.toLowerCase().contains(query))
        .toList(growable: false);
    return _buildObjectsList(
      controller: _markerSearchController,
      items: items
          .map(
            (marker) => _ObjectRow(
              name: marker.name,
              createdAt: _formatCreatedAt(marker.createdAt),
              preview: _ObjectPreview.marker(
                marker.point,
                color: _markerColor(marker.colorHex),
                shape: marker.shape,
              ),
              visible: marker.visible,
              onVisibilityChanged: (value) =>
                  _setMarkerVisibility(marker, value),
              onEdit: () async {
                if (!marker.visible) await _setMarkerVisibility(marker, true);
                if (mounted) _showOnMap(MapObjectType.marker, marker.id);
              },
              onShare: () => _shareMarker(marker),
              onDelete: () => _deleteMarker(marker),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildDrawingsTab() {
    final query = _drawingSearchController.text.trim().toLowerCase();
    final items = _drawings
        .where((drawing) => drawing.name.toLowerCase().contains(query))
        .toList(growable: false);
    return _buildObjectsList(
      controller: _drawingSearchController,
      items: items
          .map(
            (drawing) => _ObjectRow(
              name: drawing.name,
              createdAt: _formatCreatedAt(drawing.createdAt),
              preview: _ObjectPreview.path(
                drawing.points,
                polygon: drawing.type == 'polygon',
                color: Color(drawing.color),
              ),
              visible: drawing.visible,
              onVisibilityChanged: (value) =>
                  _setDrawingVisibility(drawing, value),
              onEdit: () async {
                if (!drawing.visible) {
                  await _setDrawingVisibility(drawing, true);
                }
                if (mounted) _showOnMap(MapObjectType.drawing, drawing.id);
              },
              onShare: () => _shareDrawing(drawing),
              onDelete: () => _deleteDrawing(drawing),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildTracksTab() {
    final query = _trackSearchController.text.trim().toLowerCase();
    final items = _tracks
        .where((track) => track.name.toLowerCase().contains(query))
        .toList(growable: false);
    return _buildObjectsList(
      controller: _trackSearchController,
      items: items
          .map(
            (track) => _ObjectRow(
              name: track.name,
              createdAt: _formatCreatedAt(track.createdAt),
              subtitle: () {
                final averageSpeed = track.duration <= 0
                    ? 0.0
                    : track.distance / track.duration * 3.6;
                return '${(track.distance / 1000).toStringAsFixed(2)} км · '
                    'ср. ${averageSpeed.toStringAsFixed(1)} км/ч';
              }(),
              preview: _ObjectPreview.path(
                track.points,
                color: Color(track.color),
              ),
              visible: track.visible,
              onVisibilityChanged: (value) => _setTrackVisibility(track, value),
              onEdit: () async {
                if (!track.visible) await _setTrackVisibility(track, true);
                if (mounted) _showOnMap(MapObjectType.track, track.id);
              },
              onShare: () => _shareTrack(track),
              onDelete: () => _deleteTrack(track),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildObjectsList({
    required TextEditingController controller,
    required List<Widget> items,
  }) {
    return Column(
      children: [
        _buildSearchField(controller),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Ничего не найдено'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16), children: items),
        ),
      ],
    );
  }

  Widget _buildSearchField(TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        onChanged: (_) {
          if (!mounted) return;
          setState(() {});
        },
        decoration: const InputDecoration(
          hintText: 'Поиск по названию',
          prefixIcon: Icon(Icons.search, color: Colors.white70),
          filled: true,
          fillColor: _panelColor,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Color _markerColor(String colorHex) {
    return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
  }
}

class _ObjectRow extends StatelessWidget {
  const _ObjectRow({
    required this.name,
    required this.createdAt,
    required this.preview,
    required this.visible,
    required this.onVisibilityChanged,
    required this.onDelete,
    required this.onShare,
    required this.onEdit,
    this.subtitle,
  });

  final String name;
  final String createdAt;
  final String? subtitle;
  final Widget preview;
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onEdit,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: _MyObjectsScreenState._panelColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                preview,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            color: Colors.white54,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            createdAt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.visibility, color: Colors.white70, size: 18),
                const SizedBox(width: 4),
                const Text('На карте', style: TextStyle(color: Colors.white70)),
                const Spacer(),
                IconButton(
                  tooltip: 'Открыть меню объекта',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Поделиться',
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: onShare,
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onDelete,
                ),
                Switch(
                  value: visible,
                  activeThumbColor: _MyObjectsScreenState._accentColor,
                  activeTrackColor:
                      _MyObjectsScreenState._accentColor.withValues(alpha: 0.5),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.shade700,
                  onChanged: onVisibilityChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ObjectPreview extends StatelessWidget {
  const _ObjectPreview._({
    required this.points,
    required this.color,
    this.markerPoint,
    this.markerShape = 'location_on',
    this.polygon = false,
  });

  factory _ObjectPreview.marker(
    LatLng point, {
    required Color color,
    required String shape,
  }) =>
      _ObjectPreview._(
        points: [point],
        color: color,
        markerPoint: point,
        markerShape: shape,
      );

  factory _ObjectPreview.path(
    List<LatLng> points, {
    required Color color,
    bool polygon = false,
  }) =>
      _ObjectPreview._(points: points, color: color, polygon: polygon);

  final List<LatLng> points;
  final Color color;
  final LatLng? markerPoint;
  final String markerShape;
  final bool polygon;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        width: 72,
        height: 72,
        child: ColoredBox(
          color: Color(0xFF1E1E1E),
          child: Icon(Icons.map_outlined, color: Colors.white54),
        ),
      );
    }
    final center = _center(points);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 72,
        height: 72,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: _zoomFor(points),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: MapLayers.esriWorldImagery,
              userAgentPackageName: MapLayers.userAgentPackageName,
              tileDisplay: const TileDisplay.instantaneous(),
            ),
            if (polygon && points.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: points,
                    color: color.withValues(alpha: 0.3),
                    borderColor: color,
                    borderStrokeWidth: 2,
                  ),
                ],
              )
            else if (points.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(points: points, color: color, strokeWidth: 3),
                ],
              ),
            if (markerPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: markerPoint!,
                    width: 28,
                    height: 28,
                    child: _markerIcon(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _markerIcon() => switch (markerShape) {
        'square' => Container(width: 20, height: 20, color: color),
        'triangle' => Icon(Icons.change_history, color: color, size: 26),
        'circle' => Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        'place' => Icon(Icons.place, color: color, size: 26),
        'flag' => Icon(Icons.flag, color: color, size: 26),
        'star' => Icon(Icons.star, color: color, size: 26),
        'home' => Icon(Icons.home, color: color, size: 26),
        'work' => Icon(Icons.work, color: color, size: 26),
        _ => Icon(Icons.location_on, color: color, size: 26),
      };

  static LatLng _center(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  static double _zoomFor(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    final span = math.max(maxLat - minLat, maxLng - minLng);
    if (span < 0.001) return 15;
    if (span < 0.005) return 13;
    if (span < 0.02) return 11;
    if (span < 0.08) return 9;
    return 7;
  }
}
