import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/saved_connection.dart';
import '../models/saved_query.dart';
import '../models/query_history.dart';
import 'encryption_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  // Factory constructor to return the same instance
  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Get a location using path_provider
    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, 'mydbapp_local.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE saved_connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        host TEXT,
        port INTEGER,
        username TEXT,
        password TEXT,
        database_name TEXT,
        use_ssh INTEGER,
        ssh_host TEXT,
        ssh_port INTEGER,
        ssh_username TEXT,
        ssh_password TEXT,
        ssh_key_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE saved_queries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        query TEXT,
        created_at TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE query_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT,
        executed_at TEXT,
        success INTEGER,
        execution_time_ms INTEGER
      )
    ''');
  }

  // --- Saved Connections methods ---
  Future<int> insertConnection(SavedConnection connection) async {
    final db = await database;
    var map = connection.toMap();
    
    // Encrypt passwords before saving
    if (map['password'] != null) {
      map['password'] = await EncryptionService.encrypt(map['password']);
    }
    if (map['ssh_password'] != null) {
      map['ssh_password'] = await EncryptionService.encrypt(map['ssh_password']);
    }
    
    return await db.insert('saved_connections', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<SavedConnection>> getConnections() async {
    final db = await database;
    final maps = await db.query('saved_connections');
    
    final results = <SavedConnection>[];
    for (final m in maps) {
      var map = Map<String, dynamic>.from(m);
      
      // Decrypt passwords when loading
      if (map['password'] != null) {
        map['password'] = await EncryptionService.decrypt(map['password']);
      }
      if (map['ssh_password'] != null) {
        map['ssh_password'] = await EncryptionService.decrypt(map['ssh_password']);
      }
      
      results.add(SavedConnection.fromMap(map));
    }
    return results;
  }
  
  Future<void> deleteConnection(int id) async {
    final db = await database;
    await db.delete('saved_connections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllConnections() async {
    final db = await database;
    await db.delete('saved_connections');
  }

  // --- Saved Queries methods ---
  Future<int> insertSavedQuery(SavedQuery query) async {
    final db = await database;
    return await db.insert('saved_queries', query.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SavedQuery>> getSavedQueries() async {
    final db = await database;
    final maps = await db.query('saved_queries', orderBy: 'created_at DESC');
    return List.generate(maps.length, (i) => SavedQuery.fromMap(maps[i]));
  }
  
  Future<void> deleteSavedQuery(int id) async {
    final db = await database;
    await db.delete('saved_queries', where: 'id = ?', whereArgs: [id]);
  }

  // --- Query History methods ---
  Future<int> addToHistory(QueryHistory history) async {
    final db = await database;
    final id = await db.insert('query_history', history.toMap());
    
    // Keep only latest 20
    await db.rawDelete('''
      DELETE FROM query_history 
      WHERE id NOT IN (
        SELECT id FROM query_history 
        ORDER BY executed_at DESC 
        LIMIT 20
      )
    ''');
    
    return id;
  }

  Future<List<QueryHistory>> getQueryHistory() async {
    final db = await database;
    final maps = await db.query('query_history', orderBy: 'executed_at DESC', limit: 50); // Limit to last 50
    return List.generate(maps.length, (i) => QueryHistory.fromMap(maps[i]));
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('query_history');
  }
}
