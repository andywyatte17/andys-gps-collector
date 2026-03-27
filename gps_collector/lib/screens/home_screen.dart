import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';
import 'debug_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PermissionService _permissionService = PermissionService();
  GpsPermissionResult? _permissionResult;

  Future<void> _checkPermission() async {
    final result = await _permissionService.checkGpsPermission();
    setState(() {
      _permissionResult = result;
    });
  }

  Future<void> _requestPermission() async {
    final result = await _permissionService.requestGpsPermission();
    setState(() {
      _permissionResult = result;
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
      case GpsPermissionStatus.permanentlyDenied:
        return Icons.gps_off;
      case GpsPermissionStatus.serviceDisabled:
        return Icons.location_disabled;
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: Padding(
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
          ],
        ),
      ),
    );
  }
}
