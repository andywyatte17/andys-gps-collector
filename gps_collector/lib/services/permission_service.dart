import 'package:permission_handler/permission_handler.dart';

enum GpsPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
}

class GpsPermissionResult {
  final GpsPermissionStatus status;
  final String message;

  GpsPermissionResult({required this.status, required this.message});
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

    final status = await Permission.locationWhenInUse.status;

    if (status.isGranted) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.granted,
        message: 'GPS permissions are granted. You are ready to record tracks.',
      );
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
      message:
          'GPS permission has not been granted yet.\n\n'
          'Tap "Request Permission" below to grant access.',
    );
  }

  /// Requests GPS permission from the user.
  Future<GpsPermissionResult> requestGpsPermission() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      return GpsPermissionResult(
        status: GpsPermissionStatus.granted,
        message: 'GPS permissions are granted. You are ready to record tracks.',
      );
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
}
