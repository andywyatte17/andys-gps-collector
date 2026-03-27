import 'dart:math';

/// Haversine distance between two lat/lon points, in metres.
double haversineMetres({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadiusM * c;
}

double _toRadians(double degrees) => degrees * pi / 180;

/// Sum straight-line distances between consecutive points.
/// Each point must have 'latitude' and 'longitude' keys.
double totalDistanceMetres(List<Map<String, dynamic>> points) {
  if (points.length < 2) {
    return 0;
  }

  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += haversineMetres(
      lat1: points[i - 1]['latitude'] as double,
      lon1: points[i - 1]['longitude'] as double,
      lat2: points[i]['latitude'] as double,
      lon2: points[i]['longitude'] as double,
    );
  }
  return total;
}

/// Format distance for display.
String formatDistance(double metres) {
  if (metres < 1000) {
    return '${metres.toStringAsFixed(0)} m';
  }
  return '${(metres / 1000).toStringAsFixed(2)} km';
}

/// Calculate pace as minutes per km from distance (m) and duration (ms).
/// Returns null if distance is too small.
String? formatPace({
  required double distanceMetres,
  required int durationMs,
}) {
  if (distanceMetres < 10) {
    return null;
  }

  final distanceKm = distanceMetres / 1000;
  final durationMinutes = durationMs / 60000;
  final paceMinPerKm = durationMinutes / distanceKm;

  final wholeMinutes = paceMinPerKm.floor();
  final seconds = ((paceMinPerKm - wholeMinutes) * 60).round();

  return "$wholeMinutes'${seconds.toString().padLeft(2, '0')}\" /km";
}
