import 'package:flutter/material.dart';
import '../services/database_service.dart';

class TrackEventsScreen extends StatefulWidget {
  final int trackId;
  final String trackName;

  const TrackEventsScreen({
    super.key,
    required this.trackId,
    required this.trackName,
  });

  @override
  State<TrackEventsScreen> createState() => _TrackEventsScreenState();
}

class _TrackEventsScreenState extends State<TrackEventsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await _db.getTrackEvents(trackId: widget.trackId);
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatMs(int ms) {
    final seconds = ms ~/ 1000;
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  /// Count point events in each accuracy bucket.
  ({int total, int good, int medium, int poor}) _accuracyBreakdown() {
    int good = 0;   // 0–5m
    int medium = 0; // 5–20m
    int poor = 0;   // 20m+
    for (final e in _events) {
      if (e['event_type'] != 'point') { continue; }
      final acc = e['accuracy_meters'] as double?;
      if (acc == null) { continue; }
      if (acc <= 5) {
        good++;
      } else if (acc <= 20) {
        medium++;
      } else {
        poor++;
      }
    }
    return (total: good + medium + poor, good: good, medium: medium, poor: poor);
  }

  String _pct(int count, int total) {
    if (total == 0) { return '0%'; }
    return '${(count * 100 / total).round()}%';
  }

  /// Infer the likely location provider from available data.
  String _inferSource(Map<String, dynamic> event) {
    final acc = event['accuracy_meters'] as double?;
    final altitudeAcc = event['altitude_accuracy'] as double?;
    final isMocked = event['is_mocked'] as int?;

    if (isMocked == 1) { return 'Mock'; }

    // Network fixes typically have very poor accuracy and no altitude accuracy
    if (acc != null && acc > 100 && (altitudeAcc == null || altitudeAcc == 0)) {
      return 'Network?';
    }
    // Good accuracy with altitude data strongly suggests GPS satellite fix
    if (acc != null && acc < 20 && altitudeAcc != null && altitudeAcc > 0) {
      return 'GPS';
    }
    // Moderate accuracy - likely fused provider
    if (acc != null && acc >= 20) {
      return 'Fused?';
    }
    return 'GPS?';
  }

  Future<void> _removeByAccuracy({
    required double threshold,
    required String label,
  }) async {
    // Count how many would be removed
    int count = 0;
    for (final e in _events) {
      if (e['event_type'] != 'point') { continue; }
      final acc = e['accuracy_meters'] as double?;
      if (acc != null && acc >= threshold) { count++; }
    }

    if (count == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No events with accuracy $label to remove.')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Events'),
        content: Text(
          'Remove $count point events with accuracy $label?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final removed = await _db.deletePointsByAccuracy(
        trackId: widget.trackId,
        maxAccuracyMeters: threshold,
      );
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $removed events.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trackName} — Events'),
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
              : _events.isEmpty
                  ? const Center(child: Text('No events recorded.'))
                  : Column(
                      children: [
                        _buildAccuracySummary(),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columnSpacing: 12,
                                columns: const [
                                  DataColumn(label: Text('#')),
                                  DataColumn(label: Text('Type')),
                                  DataColumn(label: Text('Time')),
                                  DataColumn(label: Text('Lat')),
                                  DataColumn(label: Text('Lon')),
                                  DataColumn(label: Text('Acc (m)')),
                                  DataColumn(label: Text('Source')),
                                  DataColumn(label: Text('Speed')),
                                  DataColumn(label: Text('Alt')),
                                  DataColumn(label: Text('Spd Acc')),
                                  DataColumn(label: Text('Alt Acc')),
                                  DataColumn(label: Text('Hdg Acc')),
                                ],
                                rows: List.generate(_events.length, (i) {
                                  final e = _events[i];
                                  final eventType = e['event_type'] as String;
                                  final ms = e['ms_since_start'] as int;
                                  final lat = e['latitude'] as double?;
                                  final lon = e['longitude'] as double?;
                                  final acc = e['accuracy_meters'] as double?;
                                  final speed = e['speed'] as double?;
                                  final altitude = e['altitude'] as double?;
                                  final speedAcc = e['speed_accuracy'] as double?;
                                  final altAcc = e['altitude_accuracy'] as double?;
                                  final hdgAcc = e['heading_accuracy'] as double?;

                                  final isPoint = eventType == 'point';
                                  final accText = acc != null
                                      ? acc.toStringAsFixed(1)
                                      : '-';
                                  final source = isPoint ? _inferSource(e) : '-';

                                  // Highlight poor accuracy in red
                                  final accStyle = acc != null && acc > 20
                                      ? const TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        )
                                      : null;

                                  // Colour-code inferred source
                                  final sourceStyle = TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: source == 'GPS'
                                        ? Colors.green
                                        : source.startsWith('Network')
                                            ? Colors.red
                                            : source == 'Mock'
                                                ? Colors.purple
                                                : Colors.orange,
                                  );

                                  return DataRow(
                                    color: !isPoint
                                        ? WidgetStateProperty.all(
                                            Colors.amber.withAlpha(40),
                                          )
                                        : null,
                                    cells: [
                                      DataCell(Text('${i + 1}')),
                                      DataCell(Text(eventType)),
                                      DataCell(Text(_formatMs(ms))),
                                      DataCell(Text(
                                        lat != null
                                            ? lat.toStringAsFixed(6)
                                            : '-',
                                      )),
                                      DataCell(Text(
                                        lon != null
                                            ? lon.toStringAsFixed(6)
                                            : '-',
                                      )),
                                      DataCell(Text(
                                        accText,
                                        style: accStyle,
                                      )),
                                      DataCell(Text(source, style: sourceStyle)),
                                      DataCell(Text(
                                        speed != null ? speed.toStringAsFixed(1) : '-',
                                      )),
                                      DataCell(Text(
                                        altitude != null ? altitude.toStringAsFixed(0) : '-',
                                      )),
                                      DataCell(Text(
                                        speedAcc != null ? speedAcc.toStringAsFixed(1) : '-',
                                      )),
                                      DataCell(Text(
                                        altAcc != null ? altAcc.toStringAsFixed(1) : '-',
                                      )),
                                      DataCell(Text(
                                        hdgAcc != null ? hdgAcc.toStringAsFixed(1) : '-',
                                      )),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildAccuracySummary() {
    final b = _accuracyBreakdown();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Text(
            '${_events.length} events',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _accChip('0-5m', b.good, b.total, Colors.green),
              const SizedBox(width: 12),
              _accChip('5-20m', b.medium, b.total, Colors.orange),
              const SizedBox(width: 12),
              _accChip('20m+', b.poor, b.total, Colors.red),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _removeByAccuracy(
                  threshold: 20,
                  label: '20m+',
                ),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove 20m+'),
              ),
              ElevatedButton(
                onPressed: () => _removeByAccuracy(
                  threshold: 5,
                  label: '5m+',
                ),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove 5m+'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accChip(String label, int count, int total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        '$label: $count (${_pct(count, total)})',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
