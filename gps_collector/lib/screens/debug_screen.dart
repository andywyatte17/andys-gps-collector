import 'package:flutter/material.dart';
import '../services/database_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  Map<String, dynamic>? _dbInfo;
  bool _loading = false;
  String? _error;

  Future<void> _loadDbInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await DatabaseService().getDebugInfo();
      setState(() {
        _dbInfo = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug - Database'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _loadDbInfo,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load DB Status'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                color: Colors.red.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'Error: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            if (_dbInfo != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Database Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      _infoRow('Path', _dbInfo!['path']),
                      _infoRow(
                        'Tables',
                        (_dbInfo!['tables'] as List).join(', '),
                      ),
                      const Divider(),
                      const Text(
                        'Tracks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _infoRow('Total tracks', '${_dbInfo!['track_count']}'),
                      _infoRow(
                        'Active tracks',
                        '${_dbInfo!['active_track_count']}',
                      ),
                      _infoRow(
                        'Total GPS points',
                        '${_dbInfo!['track_point_count']}',
                      ),
                      const Divider(),
                      const Text(
                        'Tile Cache',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _infoRow(
                        'Cached tiles',
                        '${_dbInfo!['tile_cache_count']}',
                      ),
                      _infoRow(
                        'Cache size',
                        '${_dbInfo!['tile_cache_size_mb']} MB',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
