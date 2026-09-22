import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/custom_sign.dart';
import '../../models/saved_phrase.dart';

class DatabaseService {
  DatabaseService._internal();

  static final DatabaseService instance = DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'translation.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE custom_signs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            landmark_sequence TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_phrases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertCustomSign({
    required String label,
    required String landmarkSequenceJson,
  }) async {
    final db = await database;
    return db.insert('custom_signs', {
      'label': label,
      'landmark_sequence': landmarkSequenceJson,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<CustomSign>> getCustomSigns() async {
    final db = await database;
    final rows = await db.query('custom_signs', orderBy: 'created_at DESC');
    return rows.map(CustomSign.fromMap).toList();
  }

  Future<void> deleteCustomSign(int id) async {
    final db = await database;
    await db.delete('custom_signs', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSavedPhrase(String text) async {
    final db = await database;
    return db.insert('saved_phrases', {
      'text': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<SavedPhrase>> getSavedPhrases() async {
    final db = await database;
    final rows = await db.query('saved_phrases', orderBy: 'created_at DESC');
    return rows.map(SavedPhrase.fromMap).toList();
  }

  Future<void> deleteSavedPhrase(int id) async {
    final db = await database;
    await db.delete('saved_phrases', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
