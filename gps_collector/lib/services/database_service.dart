import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'gps_collector.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tracks table - one row per run/session
    await db.execute('''
      CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        distance_meters REAL DEFAULT 0.0,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Track events - GPS points and pause/unpause markers
    await db.execute('''
      CREATE TABLE track_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        ms_since_start INTEGER NOT NULL,
        latitude REAL,
        longitude REAL,
        accuracy_meters REAL,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');

    // Tile cache for OpenStreetMap tiles
    await db.execute('''
      CREATE TABLE tile_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        z INTEGER NOT NULL,
        x INTEGER NOT NULL,
        y INTEGER NOT NULL,
        tile_data BLOB NOT NULL,
        size_bytes INTEGER NOT NULL,
        fetched_at TEXT NOT NULL,
        last_accessed_at TEXT NOT NULL,
        UNIQUE(z, x, y)
      )
    ''');

    // Index for tile lookups
    await db.execute('''
      CREATE INDEX idx_tile_cache_zxy ON tile_cache(z, x, y)
    ''');

    // Index for cache eviction (oldest accessed first)
    await db.execute('''
      CREATE INDEX idx_tile_cache_last_accessed ON tile_cache(last_accessed_at)
    ''');

    // Index for cache expiry (oldest fetched first)
    await db.execute('''
      CREATE INDEX idx_tile_cache_fetched ON tile_cache(fetched_at)
    ''');
  }

  /// Create a new track and return its ID.
  Future<int> createTrack({
    required String name,
    required String startedAt,
  }) async {
    final db = await database;
    return await db.insert('tracks', {
      'name': name,
      'started_at': startedAt,
      'is_active': 1,
    });
  }

  /// Mark a track as finished.
  Future<void> finalizeTrack({
    required int trackId,
    required String endedAt,
  }) async {
    final db = await database;
    await db.update(
      'tracks',
      {'ended_at': endedAt, 'is_active': 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  /// Insert a GPS point event for a track.
  Future<void> insertTrackPoint({
    required int trackId,
    required int msSinceStart,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    final db = await database;
    await db.insert('track_events', {
      'track_id': trackId,
      'event_type': 'point',
      'ms_since_start': msSinceStart,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
    });
  }

  /// Insert a pause event for a track.
  Future<void> insertPauseEvent({
    required int trackId,
    required int msSinceStart,
  }) async {
    final db = await database;
    await db.insert('track_events', {
      'track_id': trackId,
      'event_type': 'pause',
      'ms_since_start': msSinceStart,
    });
  }

  /// Insert an unpause event for a track.
  Future<void> insertUnpauseEvent({
    required int trackId,
    required int msSinceStart,
  }) async {
    final db = await database;
    await db.insert('track_events', {
      'track_id': trackId,
      'event_type': 'unpause',
      'ms_since_start': msSinceStart,
    });
  }

  /// Get a single track by ID.
  Future<Map<String, dynamic>?> getTrack({required int trackId}) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  /// Get all completed tracks, newest first.
  Future<List<Map<String, dynamic>>> getAllTracks() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.*,
        COUNT(CASE WHEN te.event_type = 'point' THEN 1 END) as point_count
      FROM tracks t
      LEFT JOIN track_events te ON te.track_id = t.id
      WHERE t.is_active = 0
      GROUP BY t.id
      ORDER BY t.started_at DESC
    ''');
  }

  /// Get all events for a track, in time order.
  Future<List<Map<String, dynamic>>> getTrackEvents({
    required int trackId,
  }) async {
    final db = await database;
    return await db.query(
      'track_events',
      where: 'track_id = ?',
      whereArgs: [trackId],
      orderBy: 'ms_since_start ASC',
    );
  }

  /// Get only GPS point events for a track, in time order.
  Future<List<Map<String, dynamic>>> getTrackPoints({
    required int trackId,
  }) async {
    final db = await database;
    return await db.query(
      'track_events',
      where: "track_id = ? AND event_type = 'point'",
      whereArgs: [trackId],
      orderBy: 'ms_since_start ASC',
    );
  }

  /// Returns a map of debug info about the database state.
  Future<Map<String, dynamic>> getDebugInfo() async {
    final db = await database;

    final trackCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tracks'),
    ) ?? 0;

    final activeTrackCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tracks WHERE is_active = 1'),
    ) ?? 0;

    final trackPointCount = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM track_events WHERE event_type = 'point'"),
    ) ?? 0;

    final tileCacheCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tile_cache'),
    ) ?? 0;

    final tileCacheSizeBytes = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COALESCE(SUM(size_bytes), 0) FROM tile_cache'),
    ) ?? 0;

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );

    final dbPath = db.path;

    return {
      'path': dbPath,
      'tables': tables.map((t) => t['name'] as String).toList(),
      'track_count': trackCount,
      'active_track_count': activeTrackCount,
      'track_point_count': trackPointCount,
      'tile_cache_count': tileCacheCount,
      'tile_cache_size_mb':
          (tileCacheSizeBytes / (1024 * 1024)).toStringAsFixed(2),
    };
  }
}
