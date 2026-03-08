import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/download_item.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'dirxplore_downloads.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE downloads(
        id TEXT PRIMARY KEY,
        url TEXT,
        fileName TEXT,
        savePath TEXT,
        batchId TEXT,
        batchName TEXT,
        status INTEGER,
        totalBytes INTEGER,
        downloadedBytes INTEGER,
        retryCount INTEGER,
        errorMessage TEXT,
        addedAt TEXT
      )
    ''');
  }

  Future<int> insertDownload(DownloadItem item) async {
    final db = await database;
    return await db.insert(
      'downloads',
      item.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DownloadItem>> getDownloads() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('downloads');
    return List.generate(maps.length, (i) {
      return DownloadItem.fromJson(maps[i]);
    });
  }

  Future<int> updateDownload(DownloadItem item) async {
    final db = await database;
    return await db.update(
      'downloads',
      item.toJson(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteDownload(String id) async {
    final db = await database;
    return await db.delete(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('downloads');
  }
}
