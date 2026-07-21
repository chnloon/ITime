import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/schedule_item.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'oigo.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            location TEXT DEFAULT '',
            event_time TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            is_deleted INTEGER DEFAULT 0,
            reminder_minutes INTEGER DEFAULT 0,
            ringtone_uri TEXT DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE schedules ADD COLUMN reminder_minutes INTEGER DEFAULT 0'
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE schedules ADD COLUMN ringtone_uri TEXT DEFAULT \'\''
          );
        }
      },
    );
  }

  // Insert a new schedule item
  static Future<int> insert(ScheduleItem item) async {
    final db = await database;
    return await db.insert('schedules', item.toMap());
  }

  // Update an existing schedule item
  static Future<int> update(ScheduleItem item) async {
    final db = await database;
    return await db.update(
      'schedules',
      item.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // Soft delete (move to graveyard)
  static Future<int> softDelete(int id) async {
    final db = await database;
    return await db.update(
      'schedules',
      {
        'is_deleted': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Permanently delete
  static Future<int> permanentDelete(int id) async {
    final db = await database;
    return await db.delete(
      'schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Restore from graveyard
  static Future<int> restore(int id) async {
    final db = await database;
    return await db.update(
      'schedules',
      {
        'is_deleted': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get all active (not deleted) schedules
  static Future<List<ScheduleItem>> getActiveSchedules() async {
    final db = await database;
    final maps = await db.query(
      'schedules',
      where: 'is_deleted = 0',
      orderBy: 'event_time ASC',
    );
    return maps.map((map) => ScheduleItem.fromMap(map)).toList();
  }

  // Get all deleted/expired schedules (graveyard)
  static Future<List<ScheduleItem>> getGraveyardSchedules() async {
    final db = await database;
    final maps = await db.query(
      'schedules',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => ScheduleItem.fromMap(map)).toList();
  }

  // Search in graveyard
  static Future<List<ScheduleItem>> searchGraveyard(String query) async {
    final db = await database;
    final maps = await db.query(
      'schedules',
      where: 'is_deleted = 1 AND (title LIKE ? OR description LIKE ? OR location LIKE ?)',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => ScheduleItem.fromMap(map)).toList();
  }

  // Get a single item by ID
  static Future<ScheduleItem?> getById(int id) async {
    final db = await database;
    final maps = await db.query(
      'schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return ScheduleItem.fromMap(maps.first);
  }

  // Close database
  static Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
