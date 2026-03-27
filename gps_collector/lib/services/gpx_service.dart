import 'database_service.dart';

class GpxService {
  final DatabaseService _db = DatabaseService();

  /// Generate a GPX XML string for a given track.
  Future<String> generateGpx({required int trackId}) async {
    final track = await _db.getTrack(trackId: trackId);
    final points = await _db.getTrackPoints(trackId: trackId);

    if (track == null) {
      return '';
    }

    final trackName = track['name'] as String;
    final startedAt = DateTime.parse(track['started_at'] as String);
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<gpx version="1.1" creator="GPS Collector"'
      ' xmlns="http://www.topografix.com/GPX/1/1"'
      ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
      ' xsi:schemaLocation="http://www.topografix.com/GPX/1/1'
      ' http://www.topografix.com/GPX/1/1/gpx.xsd">',
    );
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_xmlEscape(trackName)}</name>');
    buffer.writeln('    <trkseg>');

    for (final point in points) {
      final lat = point['latitude'];
      final lon = point['longitude'];
      final ms = point['ms_since_start'] as int;
      final time = startedAt.add(Duration(milliseconds: ms)).toIso8601String();

      buffer.write('      <trkpt lat="$lat" lon="$lon">');
      buffer.write('<time>$time</time>');
      buffer.writeln('</trkpt>');
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
