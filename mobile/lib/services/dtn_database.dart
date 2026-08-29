import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../core/interfaces/services.dart';

class DtnDatabaseService implements IDatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  @override
  Future<Database> initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mesh_engine.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sos_packets(
            did TEXT PRIMARY KEY,
            h3_index TEXT,
            timestamp INTEGER,
            type TEXT,
            is_synced INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE hazard_zones(
            h3_index TEXT PRIMARY KEY
          )
        ''');
      },
    );
  }

  @override
  Future<void> saveSosPacket(SosPacket packet) async {
    final db = await database;
    await db.insert(
      'sos_packets',
      packet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<SosPacket>> getUnsyncedPackets() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sos_packets',
      where: 'is_synced = ?',
      whereArgs: [0],
    );

    return List.generate(maps.length, (i) {
      return SosPacket.fromMap(maps[i]);
    });
  }

  @override
  Future<void> markPacketsAsSynced(List<String> dids) async {
    final db = await database;
    for (String did in dids) {
      await db.update(
        'sos_packets',
        {'is_synced': 1},
        where: 'did = ?',
        whereArgs: [did],
      );
    }
  }

  @override
  Future<void> cacheHazardZones(List<String> h3Indices) async {
    final db = await database;
    await db.transaction((txn) async {
      // Clear old hazards
      await txn.delete('hazard_zones');
      // Insert new
      for (String index in h3Indices) {
        await txn.insert(
          'hazard_zones',
          {'h3_index': index},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  @override
  Future<List<String>> getCachedHazardZones() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('hazard_zones');
    return List.generate(maps.length, (i) => maps[i]['h3_index'] as String);
  }
}
