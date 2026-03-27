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

    // Track points - GPS fixes linked to a track
    await db.execute('''
      CREATE TABLE track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        accuracy REAL,
        speed REAL,
        timestamp TEXT NOT NULL,
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
      await db.rawQuery('SELECT COUNT(*) FROM track_points'),
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
