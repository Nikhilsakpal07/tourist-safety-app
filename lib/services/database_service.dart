import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:posaic_app/models/sos_packet.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  final List<SosPacket> _webMemoryQueue = [];

  DatabaseService._init();

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    _database = await _initDB('posaic_mesh_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sos_queue (
            id TEXT PRIMARY KEY,
            did TEXT NOT NULL,
            h3_index TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            emergency_type TEXT NOT NULL,
            signature TEXT NOT NULL,
            is_relayed INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> insertSosPacket(SosPacket packet) async {
    if (kIsWeb) {
      // Check if already exists in mock list to avoid duplicates
      final exists = _webMemoryQueue.any((p) => p.id == packet.id);
      if (!exists) {
        _webMemoryQueue.insert(0, packet);
      }
      return;
    }
    final db = await database;
    await db?.insert('sos_queue', packet.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SosPacket>> getPendingPackets() async {
    if (kIsWeb) {
      return List.unmodifiable(_webMemoryQueue);
    }
    final db = await database;
    final maps = await db?.query('sos_queue', orderBy: 'timestamp DESC');
    if (maps == null) return [];
    return maps.map((e) => SosPacket.fromMap(e)).toList();
  }

  Future<void> markPacketAsRelayed(String packetId) async {
    if (kIsWeb) {
      final index = _webMemoryQueue.indexWhere((p) => p.id == packetId);
      if (index != -1) {
        final old = _webMemoryQueue[index];
        _webMemoryQueue[index] = SosPacket(
          id: old.id,
          did: old.did,
          h3Index: old.h3Index,
          timestamp: old.timestamp,
          emergencyType: old.emergencyType,
          signature: old.signature,
          isRelayed: 1,
        );
      }
      return;
    }
    final db = await database;
    await db?.update(
      'sos_queue',
      {'is_relayed': 1},
      where: 'id = ?',
      whereArgs: [packetId],
    );
  }

  Future<void> clearAllQueue() async {
    if (kIsWeb) {
      _webMemoryQueue.clear();
      return;
    }
    final db = await database;
    await db?.delete('sos_queue');
  }
}