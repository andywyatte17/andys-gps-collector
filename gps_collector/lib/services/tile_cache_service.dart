import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

const int _maxCacheBytes = 50 * 1024 * 1024; // 50 MB
const Duration _tileMaxAge = Duration(days: 7);

class TileCacheStats {
  int networkLoadedBytes = 0;
  int cacheHitBytes = 0;
  int networkRequests = 0;
  int cacheHits = 0;

  void reset() {
    networkLoadedBytes = 0;
    cacheHitBytes = 0;
    networkRequests = 0;
    cacheHits = 0;
  }
}

class TileCacheService {
  static final TileCacheService _instance = TileCacheService._internal();
  factory TileCacheService() => _instance;
  TileCacheService._internal();

  final DatabaseService _db = DatabaseService();
  final TileCacheStats stats = TileCacheStats();

  /// Get a tile, serving from cache if valid, otherwise fetching from network.
  Future<Uint8List?> getTile({
    required int z,
    required int x,
    required int y,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc();

    // Check cache
    final cached = await db.query(
      'tile_cache',
      where: 'z = ? AND x = ? AND y = ?',
      whereArgs: [z, x, y],
      limit: 1,
    );

    if (cached.isNotEmpty) {
      final fetchedAt = DateTime.parse(cached.first['fetched_at'] as String);
      final age = now.difference(fetchedAt);

      if (age < _tileMaxAge) {
        // Cache hit — update last_accessed_at
        await db.update(
          'tile_cache',
          {'last_accessed_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [cached.first['id']],
        );
        final data = cached.first['tile_data'] as Uint8List;
        stats.cacheHits++;
        stats.cacheHitBytes += data.length;
        return data;
      }

      // Expired — try to fetch new, fall back to stale if network fails
      final freshData = await _fetchFromNetwork(z: z, x: x, y: y);
      if (freshData != null) {
        await _upsertTile(db: db, z: z, x: x, y: y, data: freshData, now: now);
        return freshData;
      }
      // Network failed, serve stale
      final data = cached.first['tile_data'] as Uint8List;
      stats.cacheHits++;
      stats.cacheHitBytes += data.length;
      return data;
    }

    // Not in cache — fetch from network
    final data = await _fetchFromNetwork(z: z, x: x, y: y);
    if (data != null) {
      await _upsertTile(db: db, z: z, x: x, y: y, data: data, now: now);
      await _evictIfNeeded(db);
    }
    return data;
  }

  Future<Uint8List?> _fetchFromNetwork({
    required int z,
    required int x,
    required int y,
  }) async {
    final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'GPSCollectorApp/1.0'},
      );
      if (response.statusCode == 200) {
        stats.networkRequests++;
        stats.networkLoadedBytes += response.bodyBytes.length;
        return response.bodyBytes;
      }
    } catch (_) {
      // Network error — return null
    }
    return null;
  }

  Future<void> _upsertTile({
    required dynamic db,
    required int z,
    required int x,
    required int y,
    required Uint8List data,
    required DateTime now,
  }) async {
    await db.rawInsert(
      '''INSERT OR REPLACE INTO tile_cache (z, x, y, tile_data, size_bytes, fetched_at, last_accessed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [z, x, y, data, data.length, now.toIso8601String(), now.toIso8601String()],
    );
  }

  /// Evict oldest-accessed tiles until cache is under the size limit.
  Future<void> _evictIfNeeded(dynamic db) async {
    final totalBytes = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COALESCE(SUM(size_bytes), 0) FROM tile_cache'),
    ) ?? 0;

    if (totalBytes <= _maxCacheBytes) {
      return;
    }

    var bytesToFree = totalBytes - _maxCacheBytes;
    final oldest = await db.rawQuery(
      'SELECT id, size_bytes FROM tile_cache ORDER BY last_accessed_at ASC LIMIT 100',
    );

    for (final row in oldest) {
      if (bytesToFree <= 0) {
        break;
      }
      await db.delete('tile_cache', where: 'id = ?', whereArgs: [row['id']]);
      bytesToFree -= (row['size_bytes'] as int);
    }
  }

  /// Get cache statistics for the debug page.
  Future<Map<String, dynamic>> getCacheDebugInfo() async {
    final db = await _db.database;

    final tileCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tile_cache'),
    ) ?? 0;

    final totalBytes = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COALESCE(SUM(size_bytes), 0) FROM tile_cache'),
    ) ?? 0;

    return {
      'tile_count': tileCount,
      'cache_size_mb': (totalBytes / (1024 * 1024)).toStringAsFixed(2),
      'session_network_requests': stats.networkRequests,
      'session_network_loaded_mb':
          (stats.networkLoadedBytes / (1024 * 1024)).toStringAsFixed(3),
      'session_cache_hits': stats.cacheHits,
      'session_cache_served_mb':
          (stats.cacheHitBytes / (1024 * 1024)).toStringAsFixed(3),
    };
  }
}
