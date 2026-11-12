import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../config/app_config.dart';

/// Local SQLite cache for location data collected while offline.
///
/// When the device has no internet connection, location updates are stored
/// locally in this database. Once connectivity is restored, cached entries
/// are batch-uploaded to Firebase and marked as synced.
class LocationCacheService {
  static final LocationCacheService _instance = LocationCacheService._internal();
  factory LocationCacheService() => _instance;
  LocationCacheService._internal();

  Database? _db;

  /// Initialize the SQLite database
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbFile = '$dbPath/Flockar_location_cache.db';

    return openDatabase(
      dbFile,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            family_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy REAL,
            altitude REAL,
            speed REAL,
            heading REAL,
            battery INTEGER,
            is_charging INTEGER DEFAULT 0,
            network_status TEXT,
            timestamp INTEGER NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');

        // Index for efficient batch queries
        await db.execute('''
          CREATE INDEX idx_synced_timestamp 
          ON cached_locations (synced, timestamp)
        ''');
      },
    );
  }

  /// Cache a location data point (called when Firebase push fails)
  Future<void> cacheLocation({
    required String userId,
    required String familyId,
    required Map<String, dynamic> locationData,
  }) async {
    try {
      final db = await database;

      await db.insert('cached_locations', {
        'user_id': userId,
        'family_id': familyId,
        'latitude': locationData['latitude'],
        'longitude': locationData['longitude'],
        'accuracy': locationData['accuracy'],
        'altitude': locationData['altitude'],
        'speed': locationData['speed'],
        'heading': locationData['heading'],
        'battery': locationData['battery'],
        'is_charging': (locationData['isCharging'] == true) ? 1 : 0,
        'network_status': locationData['networkStatus'],
        'timestamp': locationData['timestamp'],
        'synced': 0,
      });

      // Prune if over limit
      await _pruneIfNeeded(db);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to cache location: $e');
      }
    }
  }

  /// Get un-synced location entries for batch upload
  Future<List<Map<String, dynamic>>> getPendingLocations({
    int limit = AppConfig.offlineBatchUploadSize,
  }) async {
    final db = await database;
    return db.query(
      'cached_locations',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Get the count of pending (un-synced) entries
  Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cached_locations WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Mark specific entries as synced after successful upload
  Future<void> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;

    // Use batch for efficiency
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'cached_locations',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Convert a cached row back to the Firebase location data format
  Map<String, dynamic> rowToLocationData(Map<String, dynamic> row) {
    return {
      'latitude': row['latitude'],
      'longitude': row['longitude'],
      'accuracy': row['accuracy'],
      'altitude': row['altitude'],
      'speed': row['speed'],
      'heading': row['heading'],
      'battery': row['battery'],
      'isCharging': row['is_charging'] == 1,
      'networkStatus': row['network_status'] ?? 'offline',
      'timestamp': row['timestamp'],
      'isActive': true,
    };
  }

  /// Delete synced entries older than retention period, or prune oldest
  /// entries if the cache exceeds [AppConfig.maxCachedLocations].
  Future<void> _pruneIfNeeded(Database db) async {
    // Delete old synced entries
    final cutoff = DateTime.now()
        .subtract(const Duration(days: AppConfig.cachedLocationRetentionDays))
        .millisecondsSinceEpoch;

    await db.delete(
      'cached_locations',
      where: 'synced = 1 AND timestamp < ?',
      whereArgs: [cutoff],
    );

    // If still over limit, delete oldest synced entries first
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM cached_locations'),
    ) ?? 0;

    if (count > AppConfig.maxCachedLocations) {
      final excess = count - AppConfig.maxCachedLocations;
      await db.rawDelete('''
        DELETE FROM cached_locations 
        WHERE id IN (
          SELECT id FROM cached_locations 
          ORDER BY synced DESC, timestamp ASC 
          LIMIT ?
        )
      ''', [excess]);
    }
  }

  /// Clear all cached data (e.g., on sign-out)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('cached_locations');
  }

  /// Close the database
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
