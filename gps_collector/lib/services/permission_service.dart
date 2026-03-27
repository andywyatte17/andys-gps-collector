import 'package:permission_handler/permission_handler.dart';

enum GpsPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
  backgroundNeeded,
}

class GpsPermissionResult {
  final GpsPermissionStatus status;
  final String message;

  GpsPermissionResult({required this.status, required this.message});
}

class BatteryOptimizationResult {
  final bool isExempt;
  final String message;

  BatteryOptimizationResult({required this.isExempt, required this.message});
}

class PermissionService {
  /// Checks current GPS permission state without requesting anything.
  Future<GpsPermissionResult> checkGpsPermission() async {
    final serviceEnabled = await Permission.location.serviceStatus;
    if (!serviceEnabled.isEnabled) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.serviceDisabled,
        message:
            'Location services are disabled.\n\n'
            'Please enable them:\n'
            '  1. Open your device Settings\n'
            '  2. Go to Location\n'
            '  3. Toggle Location on',
      );
    }

    final foregroundStatus = await Permission.locationWhenInUse.status;

    if (!foregroundStatus.isGranted) {
      if (foregroundStatus.isPermanentlyDenied) {
        return GpsPermissionResult(
          status: GpsPermissionStatus.permanentlyDenied,
          message:
              'GPS permission has been permanently denied.\n\n'
              'To fix this:\n'
              '  1. Open your device Settings\n'
              '  2. Go to Apps > GPS Collector > Permissions\n'
              '  3. Tap Location and select "Allow only while using the app"',
        );
      }

      return GpsPermissionResult(
        status: GpsPermissionStatus.denied,
        message:
            'GPS permission has not been granted yet.\n\n'
            'Tap "Request Permission" below to grant access.',
      );
    }

    // Foreground granted — check background
    final backgroundStatus = await Permission.locationAlways.status;

    if (!backgroundStatus.isGranted) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.backgroundNeeded,
        message:
            'Foreground GPS is granted, but background location is needed '
            'to keep tracking when the screen is off.\n\n'
            'Tap "Request Background" below, then select '
            '"Allow all the time" in the system dialog.',
      );
    }

    return GpsPermissionResult(
      status: GpsPermissionStatus.granted,
      message:
          'GPS permissions are fully granted (foreground + background). '
          'You are ready to record tracks.',
    );
  }

  /// Requests foreground GPS permission from the user.
  Future<GpsPermissionResult> requestGpsPermission() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      // Now check if we also need background
      return await checkGpsPermission();
    }

    if (status.isPermanentlyDenied) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.permanentlyDenied,
        message:
            'GPS permission has been permanently denied.\n\n'
            'To fix this:\n'
            '  1. Open your device Settings\n'
            '  2. Go to Apps > GPS Collector > Permissions\n'
            '  3. Tap Location and select "Allow only while using the app"',
      );
    }

    return GpsPermissionResult(
      status: GpsPermissionStatus.denied,
      message: 'GPS permission was denied. Please try again.',
    );
  }

  /// Requests background location permission (Android "Allow all the time").
  Future<GpsPermissionResult> requestBackgroundPermission() async {
    final status = await Permission.locationAlways.request();

    if (status.isGranted) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.granted,
        message:
            'GPS permissions are fully granted (foreground + background). '
            'You are ready to record tracks.',
      );
    }

    if (status.isPermanentlyDenied) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.permanentlyDenied,
        message:
            'Background location has been permanently denied.\n\n'
            'To fix this:\n'
            '  1. Open your device Settings\n'
            '  2. Go to Apps > GPS Collector > Permissions\n'
            '  3. Tap Location and select "Allow all the time"',
      );
    }

    return GpsPermissionResult(
      status: GpsPermissionStatus.backgroundNeeded,
      message:
          'Background location was denied. Tracking may stop when the '
          'screen is off. Please try again.',
    );
  }

  /// Check if battery optimization is disabled for this app.
  Future<BatteryOptimizationResult> checkBatteryOptimization() async {
    final isExempt =
        await Permission.ignoreBatteryOptimizations.status.isGranted;

    if (isExempt) {
      return BatteryOptimizationResult(
        isExempt: true,
        message: 'Battery optimization is disabled for this app. Good.',
      );
    }

    return BatteryOptimizationResult(
      isExempt: false,
      message:
          'Battery optimization is enabled, which may kill GPS tracking '
          'in the background.\n\n'
          'Tap "Disable Battery Optimization" to fix this.',
    );
  }

  /// Request to disable battery optimization for this app.
  Future<BatteryOptimizationResult> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();

    if (status.isGranted) {
      return BatteryOptimizationResult(
        isExempt: true,
        message: 'Battery optimization is disabled for this app. Good.',
      );
    }

    return BatteryOptimizationResult(
      isExempt: false,
      message:
          'Request was denied. You can manually disable it:\n'
          '  1. Open Settings > Apps > GPS Collector\n'
          '  2. Tap Battery\n'
          '  3. Select "Unrestricted"',
    );
  }
}
