import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';
import '../services/tracking_service.dart';
import 'debug_screen.dart';
import 'tracks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PermissionService _permissionService = PermissionService();
  final TrackingService _trackingService = TrackingService();
  GpsPermissionResult? _permissionResult;
  BatteryOptimizationResult? _batteryResult;
  bool _showDebugPanel = false;

  @override
  void initState() {
    super.initState();
    _trackingService.onPositionUpdate = (_) {
      setState(() {});
    };
  }

  @override
  void dispose() {
    _trackingService.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final result = await _permissionService.checkGpsPermission();
    final battery = await _permissionService.checkBatteryOptimization();
    setState(() {
      _permissionResult = result;
      _batteryResult = battery;
    });
  }

  Future<void> _requestPermission() async {
    final result = await _permissionService.requestGpsPermission();
    setState(() {
      _permissionResult = result;
    });
  }

  Future<void> _requestBackground() async {
    final result = await _permissionService.requestBackgroundPermission();
    setState(() {
      _permissionResult = result;
    });
  }

  Future<void> _requestBatteryExemption() async {
    final result =
        await _permissionService.requestBatteryOptimizationExemption();
    setState(() {
      _batteryResult = result;
    });
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Color _statusColor() {
    if (_permissionResult == null) {
      return Colors.grey;
    }
    switch (_permissionResult!.status) {
      case GpsPermissionStatus.granted:
        return Colors.green;
      case GpsPermissionStatus.denied:
        return Colors.orange;
      case GpsPermissionStatus.backgroundNeeded:
        return Colors.orange;
      case GpsPermissionStatus.permanentlyDenied:
        return Colors.red;
      case GpsPermissionStatus.serviceDisabled:
        return Colors.red;
    }
  }

  IconData _statusIcon() {
    if (_permissionResult == null) {
      return Icons.gps_off;
    }
    switch (_permissionResult!.status) {
      case GpsPermissionStatus.granted:
        return Icons.gps_fixed;
      case GpsPermissionStatus.denied:
        return Icons.gps_not_fixed;
      case GpsPermissionStatus.backgroundNeeded:
        return Icons.gps_not_fixed;
      case GpsPermissionStatus.permanentlyDenied:
        return Icons.gps_off;
      case GpsPermissionStatus.serviceDisabled:
        return Icons.location_disabled;
    }
  }

  Future<void> _onRecord() async {
    // Check permission first
    final permResult = await _permissionService.checkGpsPermission();
    if (permResult.status != GpsPermissionStatus.granted) {
      setState(() {
        _permissionResult = permResult;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS permission required. Check status above.'),
          ),
        );
      }
      return;
    }

    if (_trackingService.state == TrackingState.paused) {
      await _trackingService.resume();
    } else {
      await _trackingService.startRecording();
    }
    setState(() {});
  }

  Future<void> _onPause() async {
    await _trackingService.pause();
    setState(() {});
  }

  Future<void> _onStop() async {
    await _trackingService.stop();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track saved.')),
      );
    }
  }

  String _inferSource(Position pos) {
    if (pos.isMocked) { return 'Mock'; }
    if (pos.accuracy > 100 && pos.altitudeAccuracy == 0) { return 'Network?'; }
    if (pos.accuracy < 20 && pos.altitudeAccuracy > 0) { return 'GPS'; }
    if (pos.accuracy >= 20) { return 'Fused?'; }
    return 'GPS?';
  }

  Widget _buildDebugPanel() {
    final pos = _trackingService.lastPosition;
    if (pos == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withAlpha(76)),
        ),
        child: const Text(
          'No GPS data yet. Start recording to see live data.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final source = _inferSource(pos);
    final sourceColor = source == 'GPS'
        ? Colors.green
        : source.startsWith('Network')
            ? Colors.red
            : source == 'Mock'
                ? Colors.purple
                : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Source: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(source,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: sourceColor)),
              const Spacer(),
              Text('Acc: ${pos.accuracy.toStringAsFixed(1)}m',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pos.accuracy > 20 ? Colors.red : Colors.green,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text('Lat: ${pos.latitude.toStringAsFixed(6)}  '
              'Lon: ${pos.longitude.toStringAsFixed(6)}'),
          Text('Speed: ${pos.speed.toStringAsFixed(1)} m/s  '
              'Alt: ${pos.altitude.toStringAsFixed(0)}m'),
          Text('Spd Acc: ${pos.speedAccuracy.toStringAsFixed(1)}  '
              'Alt Acc: ${pos.altitudeAccuracy.toStringAsFixed(1)}  '
              'Hdg Acc: ${pos.headingAccuracy.toStringAsFixed(1)}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackingState = _trackingService.state;
    final isRecording = trackingState == TrackingState.recording;
    final isPaused = trackingState == TrackingState.paused;
    final isActive = isRecording || isPaused;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Collector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug DB',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DebugScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // GPS Permission Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_statusIcon(), color: _statusColor(), size: 28),
                        const SizedBox(width: 8),
                        const Text(
                          'GPS Permission',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _checkPermission,
                      icon: const Icon(Icons.search),
                      label: const Text('Check GPS Permission'),
                    ),
                    if (_permissionResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusColor().withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _statusColor().withAlpha(76),
                          ),
                        ),
                        child: Text(_permissionResult!.message),
                      ),
                      const SizedBox(height: 8),
                      if (_permissionResult!.status ==
                          GpsPermissionStatus.denied)
                        ElevatedButton.icon(
                          onPressed: _requestPermission,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Request Permission'),
                        ),
                      if (_permissionResult!.status ==
                          GpsPermissionStatus.backgroundNeeded)
                        ElevatedButton.icon(
                          onPressed: _requestBackground,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Request Background'),
                        ),
                      if (_permissionResult!.status ==
                          GpsPermissionStatus.permanentlyDenied)
                        ElevatedButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings),
                          label: const Text('Open App Settings'),
                        ),
                      if (_permissionResult!.status ==
                          GpsPermissionStatus.serviceDisabled)
                        ElevatedButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings),
                          label: const Text('Open Settings'),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            // Battery Optimization Section
            if (_batteryResult != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _batteryResult!.isExempt
                                ? Icons.battery_full
                                : Icons.battery_alert,
                            color: _batteryResult!.isExempt
                                ? Colors.green
                                : Colors.orange,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Battery Optimization',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_batteryResult!.isExempt
                                  ? Colors.green
                                  : Colors.orange)
                              .withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_batteryResult!.isExempt
                                    ? Colors.green
                                    : Colors.orange)
                                .withAlpha(76),
                          ),
                        ),
                        child: Text(_batteryResult!.message),
                      ),
                      if (!_batteryResult!.isExempt) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _requestBatteryExemption,
                          icon: const Icon(Icons.battery_saver),
                          label: const Text('Disable Battery Optimization'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // GPS Tracking Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isRecording
                              ? Icons.fiber_manual_record
                              : isPaused
                                  ? Icons.pause_circle
                                  : Icons.radio_button_unchecked,
                          color: isRecording
                              ? Colors.red
                              : isPaused
                                  ? Colors.orange
                                  : Colors.grey,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isRecording
                              ? 'Recording...'
                              : isPaused
                                  ? 'Paused'
                                  : 'GPS Tracking',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Points collected: ${_trackingService.pointCount}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.bug_report,
                              color: _showDebugPanel
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            tooltip: 'Toggle GPS debug info',
                            onPressed: () {
                              setState(() {
                                _showDebugPanel = !_showDebugPanel;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    if (_showDebugPanel && isActive) ...[
                      const SizedBox(height: 4),
                      _buildDebugPanel(),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Record / Resume button
                        ElevatedButton.icon(
                          onPressed: isRecording ? null : _onRecord,
                          icon: const Icon(Icons.fiber_manual_record),
                          label: Text(isPaused ? 'Resume' : 'Record'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                isRecording ? Colors.grey : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Pause button (only active when recording)
                        ElevatedButton.icon(
                          onPressed: isRecording ? _onPause : null,
                          icon: const Icon(Icons.pause),
                          label: const Text('Pause'),
                        ),
                        const SizedBox(width: 8),
                        // Stop button (active when recording or paused)
                        ElevatedButton.icon(
                          onPressed: isActive ? _onStop : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Show Tracks button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TracksScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.list),
              label: const Text('Show Recorded Tracks'),
            ),
          ],
        ),
      ),
    );
  }
}
