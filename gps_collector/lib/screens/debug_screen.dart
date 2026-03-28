import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/tile_cache_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  Map<String, dynamic>? _dbInfo;
  Map<String, dynamic>? _cacheInfo;
  bool _loading = false;
  String? _error;

  Future<void> _loadDbInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await DatabaseService().getDebugInfo();
      final cacheInfo = await TileCacheService().getCacheDebugInfo();
      setState(() {
        _dbInfo = info;
        _cacheInfo = cacheInfo;
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
      body: SingleChildScrollView(
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
                        'Size on disk',
                        '${_dbInfo!['db_size_mb']} MB',
                      ),
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
                    ],
                  ),
                ),
              ),
            ],
            if (_cacheInfo != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tile Cache (SQLite)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      _infoRow(
                        'Cached tiles',
                        '${_cacheInfo!['tile_count']}',
                      ),
                      _infoRow(
                        'Cache size',
                        '${_cacheInfo!['cache_size_mb']} MB',
                      ),
                      const Divider(),
                      const Text(
                        'Session Stats',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _infoRow(
                        'Network requests',
                        '${_cacheInfo!['session_network_requests']}',
                      ),
                      _infoRow(
                        'Network loaded',
                        '${_cacheInfo!['session_network_loaded_mb']} MB',
                      ),
                      _infoRow(
                        'Cache hits',
                        '${_cacheInfo!['session_cache_hits']}',
                      ),
                      _infoRow(
                        'Cache served',
                        '${_cacheInfo!['session_cache_served_mb']} MB',
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
