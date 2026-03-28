import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/cached_tile_provider.dart';
import '../services/database_service.dart';

class MapScreen extends StatefulWidget {
  final int trackId;
  final String trackName;

  const MapScreen({
    super.key,
    required this.trackId,
    required this.trackName,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final DatabaseService _db = DatabaseService();
  final MapController _mapController = MapController();

  List<Map<String, dynamic>> _rawPoints = [];
  List<LatLng> _trackPoints = [];
  LatLng? _center;
  double _zoom = 15;
  bool _loading = true;
  String? _error;
  int _lineStyle = 0; // 0 = blue, 1 = green
  int _accuracyFilter = 0; // index into _accuracyFilters

  static const double _minZoom = 13;
  static const double _maxZoom = 17;

  static const _lineStyles = [
    (label: 'Blue', color: Colors.blue),
    (label: 'Green', color: Colors.green),
    (label: 'Orange', color: Colors.deepOrange),
  ];

  static const _accuracyFilters = [
    (label: 'All', maxMeters: 0.0),
    (label: '20m', maxMeters: 20.0),
    (label: '10m', maxMeters: 10.0),
    (label: '5m', maxMeters: 5.0),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTrackPoints();
  }

  Future<void> _loadSettings() async {
    final savedStyle = await _db.getSetting(key: 'map_line_style');
    final savedFilter = await _db.getSetting(key: 'map_accuracy_filter');
    setState(() {
      if (savedStyle != null) {
        final index = int.tryParse(savedStyle);
        if (index != null && index >= 0 && index < _lineStyles.length) {
          _lineStyle = index;
        }
      }
      if (savedFilter != null) {
        final index = int.tryParse(savedFilter);
        if (index != null && index >= 0 && index < _accuracyFilters.length) {
          _accuracyFilter = index;
        }
      }
    });
  }

  Future<void> _setLineStyle(int index) async {
    setState(() { _lineStyle = index; });
    await _db.setSetting(key: 'map_line_style', value: index.toString());
  }

  Future<void> _setAccuracyFilter(int index) async {
    setState(() {
      _accuracyFilter = index;
      _trackPoints = _applyAccuracyFilter(_rawPoints);
    });
    await _db.setSetting(key: 'map_accuracy_filter', value: index.toString());
  }

  List<LatLng> _applyAccuracyFilter(List<Map<String, dynamic>> points) {
    final maxMeters = _accuracyFilters[_accuracyFilter].maxMeters;
    return points
        .where((p) {
          if (maxMeters <= 0) { return true; }
          final accuracy = p['accuracy_meters'] as double?;
          return accuracy != null && accuracy <= maxMeters;
        })
        .map((p) => LatLng(
              p['latitude'] as double,
              p['longitude'] as double,
            ))
        .toList();
  }

  Future<void> _loadTrackPoints() async {
    try {
      final points = await _db.getTrackPoints(trackId: widget.trackId);
      final latLngs = _applyAccuracyFilter(points);

      LatLng center;
      if (latLngs.isNotEmpty) {
        // Centre on the bounding box midpoint
        var minLat = latLngs.first.latitude;
        var maxLat = latLngs.first.latitude;
        var minLon = latLngs.first.longitude;
        var maxLon = latLngs.first.longitude;

        for (final p in latLngs) {
          if (p.latitude < minLat) { minLat = p.latitude; }
          if (p.latitude > maxLat) { maxLat = p.latitude; }
          if (p.longitude < minLon) { minLon = p.longitude; }
          if (p.longitude > maxLon) { maxLon = p.longitude; }
        }

        center = LatLng(
          (minLat + maxLat) / 2,
          (minLon + maxLon) / 2,
        );
      } else {
        // Default to London if no points
        center = const LatLng(51.5, -0.1);
      }

      setState(() {
        _rawPoints = points;
        _trackPoints = latLngs;
        _center = center;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _zoomIn() {
    if (_zoom < _maxZoom) {
      setState(() { _zoom++; });
      _mapController.move(_mapController.camera.center, _zoom);
    }
  }

  void _zoomOut() {
    if (_zoom > _minZoom) {
      setState(() { _zoom--; });
      _mapController.move(_mapController.camera.center, _zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trackName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center!,
                        initialZoom: _zoom,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          tileProvider: CachedTileProvider(),
                          userAgentPackageName: 'com.example.gps_collector',
                        ),
                        if (_trackPoints.length >= 2)
                          PolylineLayer(
                            polylines: [
                              // Black border line (drawn first, underneath)
                              Polyline(
                                points: _trackPoints,
                                color: Colors.black.withAlpha(102),
                                strokeWidth: 7.0,
                              ),
                              // Fill line (drawn on top)
                              Polyline(
                                points: _trackPoints,
                                color: _lineStyles[_lineStyle].color.withAlpha(102),
                                strokeWidth: 5.0,
                              ),
                            ],
                          ),
                      ],
                    ),
                    // Line style & accuracy filter toggles
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'accuracy_filter',
                            backgroundColor: _accuracyFilter == 0
                                ? Colors.grey
                                : Colors.teal,
                            onPressed: () {
                              _setAccuracyFilter(
                                (_accuracyFilter + 1) % _accuracyFilters.length,
                              );
                            },
                            child: Text(
                              _accuracyFilters[_accuracyFilter].label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'line_style',
                            backgroundColor: _lineStyles[_lineStyle].color,
                            onPressed: () {
                              _setLineStyle((_lineStyle + 1) % _lineStyles.length);
                            },
                            child: Text(
                              _lineStyles[_lineStyle].label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Zoom controls
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Column(
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'zoom_in',
                            onPressed: _zoom < _maxZoom ? _zoomIn : null,
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(204),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_zoom.toInt()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_out',
                            onPressed: _zoom > _minZoom ? _zoomOut : null,
                            child: const Icon(Icons.remove),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
