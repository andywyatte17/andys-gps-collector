import 'dart:io';
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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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
        speed REAL,
        altitude REAL,
        speed_accuracy REAL,
        altitude_accuracy REAL,
        heading_accuracy REAL,
        is_mocked INTEGER,
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

    // Settings table - key/value store for app preferences
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE track_events ADD COLUMN speed REAL');
      await db.execute('ALTER TABLE track_events ADD COLUMN altitude REAL');
      await db.execute('ALTER TABLE track_events ADD COLUMN speed_accuracy REAL');
      await db.execute('ALTER TABLE track_events ADD COLUMN altitude_accuracy REAL');
      await db.execute('ALTER TABLE track_events ADD COLUMN heading_accuracy REAL');
      await db.execute('ALTER TABLE track_events ADD COLUMN is_mocked INTEGER');
    }
  }

  /// Run VACUUM to reclaim space, only if the db exceeds [thresholdBytes].
  Future<void> vacuumIfNeeded(int thresholdBytes) async {
    final db = await database;
    final dbFile = File(db.path);
    if (await dbFile.exists()) {
      final sizeBytes = await dbFile.length();
      if (sizeBytes < thresholdBytes) {
        return;
      }
    }
    await db.execute('VACUUM');
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

  /// Delete a track and all its events.
  Future<void> deleteTrack({required int trackId}) async {
    final db = await database;
    await db.delete('track_events', where: 'track_id = ?', whereArgs: [trackId]);
    await db.delete('tracks', where: 'id = ?', whereArgs: [trackId]);
  }

  /// Delete point events from a track where accuracy exceeds a threshold.
  Future<int> deletePointsByAccuracy({
    required int trackId,
    required double maxAccuracyMeters,
  }) async {
    final db = await database;
    return await db.delete(
      'track_events',
      where: "track_id = ? AND event_type = 'point' AND accuracy_meters >= ?",
      whereArgs: [trackId, maxAccuracyMeters],
    );
  }

  /// Rename a track.
  Future<void> renameTrack({
    required int trackId,
    required String name,
  }) async {
    final db = await database;
    await db.update(
      'tracks',
      {'name': name},
      where: 'id = ?',
      whereArgs: [trackId],
    );
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
    double? speed,
    double? altitude,
    double? speedAccuracy,
    double? altitudeAccuracy,
    double? headingAccuracy,
    bool? isMocked,
  }) async {
    final db = await database;
    await db.insert('track_events', {
      'track_id': trackId,
      'event_type': 'point',
      'ms_since_start': msSinceStart,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'speed': speed,
      'altitude': altitude,
      'speed_accuracy': speedAccuracy,
      'altitude_accuracy': altitudeAccuracy,
      'heading_accuracy': headingAccuracy,
      'is_mocked': isMocked == true ? 1 : null,
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

  /// Get a setting value, or null if not set.
  Future<String?> getSetting({required String key}) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return results.first['value'] as String;
  }

  /// Set a setting value (insert or update).
  Future<void> setSetting({
    required String key,
    required String value,
  }) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      [key, value],
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

    int dbSizeBytes = 0;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      dbSizeBytes = await dbFile.length();
    }

    return {
      'path': dbPath,
      'db_size_bytes': dbSizeBytes,
      'db_size_mb': (dbSizeBytes / (1024 * 1024)).toStringAsFixed(2),
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
