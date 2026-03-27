import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/gpx_service.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final DatabaseService _db = DatabaseService();
  final GpxService _gpx = GpxService();
  List<Map<String, dynamic>> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  String? _error;

  Future<void> _loadTracks() async {
    try {
      final tracks = await _db.getAllTracks();
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _copyGpx(int trackId) async {
    final gpxData = await _gpx.generateGpx(trackId: trackId);
    await Clipboard.setData(ClipboardData(text: gpxData));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPX copied to clipboard')),
      );
    }
  }

  Future<void> _saveGpx(int trackId, String trackName) async {
    final gpxData = await _gpx.generateGpx(trackId: trackId);

    // Sanitize filename
    final safeName = trackName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');

    try {
      // Try Downloads first, fall back to app documents
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final file = File('${dir.path}/$safeName.gpx');
      await file.writeAsString(gpxData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) {
      return '-';
    }
    final dt = DateTime.tryParse(isoString);
    if (dt == null) {
      return isoString;
    }
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded Tracks'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : _tracks.isEmpty
              ? const Center(child: Text('No recorded tracks yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    final trackId = track['id'] as int;
                    final name = track['name'] as String;
                    final startedAt = _formatDateTime(
                      track['started_at'] as String?,
                    );
                    final endedAt = _formatDateTime(
                      track['ended_at'] as String?,
                    );
                    final pointCount = track['point_count'] as int;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Started: $startedAt'),
                            Text('Ended: $endedAt'),
                            Text('GPS points: $pointCount'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _copyGpx(trackId),
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copy GPX'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _saveGpx(trackId, name),
                                  icon: const Icon(Icons.save, size: 18),
                                  label: const Text('Save GPX'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
