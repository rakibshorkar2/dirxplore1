import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/proxy_model.dart';
import '../services/dio_client.dart';

class AppProxyProvider with ChangeNotifier {
  List<ProxyModel> _proxies = [];
  Database? _db;

  List<ProxyModel> get proxies => _proxies;
  ProxyModel? get activeProxy => _proxies.where((p) => p.isActive).firstOrNull;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'proxies.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE proxies (
            id TEXT PRIMARY KEY,
            protocol INTEGER,
            host TEXT,
            port INTEGER,
            username TEXT,
            password TEXT,
            isActive INTEGER
          )
        ''');
      },
    );
    await _loadProxies();
  }

  Future<void> _loadProxies() async {
    if (_db == null) return;
    final maps = await _db!.query('proxies');
    
    if (maps.isEmpty) {
      final defaultProxy = ProxyModel.fromUri('socks5://test:test@103.166.253.92:1088');
      if (defaultProxy != null) {
        defaultProxy.isActive = true;
        await _db!.insert('proxies', defaultProxy.toMap());
        return _loadProxies(); // Reload after insert
      }
    }
    
    _proxies = maps.map((m) => ProxyModel.fromMap(m)).toList();
    
    // Automatically apply active proxy to Dio
    final active = activeProxy;
    DioClient().setProxy(active);
    
    notifyListeners();
  }

  Future<void> addProxy(ProxyModel proxy) async {
    if (_db == null) return;
    await _db!.insert('proxies', proxy.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadProxies();
  }

  Future<void> updateProxy(ProxyModel proxy) async {
    if (_db == null) return;
    await _db!.update('proxies', proxy.toMap(), where: 'id = ?', whereArgs: [proxy.id]);
    await _loadProxies();
  }

  Future<void> deleteProxy(String id) async {
    if (_db == null) return;
    await _db!.delete('proxies', where: 'id = ?', whereArgs: [id]);
    await _loadProxies();
  }

  Future<void> toggleProxy(String id, bool active) async {
    if (_db == null) return;
    
    // If turning one on, turn all others off first
    if (active) {
      await _db!.update('proxies', {'isActive': 0});
    }
    
    await _db!.update('proxies', {'isActive': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await _loadProxies();
  }

  Future<void> testProxyLatency(ProxyModel proxy) async {
    final ms = await DioClient().pingProxy(proxy);
    final idx = _proxies.indexWhere((p) => p.id == proxy.id);
    if (idx != -1) {
      _proxies[idx].latencyMs = ms;
      notifyListeners();
    }
  }
}
