import 'package:sqflite/sqflite.dart';
import '../../../core/errors/failures.dart';
import '../../models/reading_progress_model.dart';
import 'database_helper.dart';

class ProgressLocalDatasource {
  final DatabaseHelper _db;
  ProgressLocalDatasource({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  Future<ReadingProgressModel> getProgress(String bookId) async {
    final db = await _db.database;
    final maps = await db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );

    if (maps.isEmpty) {
      return ReadingProgressModel.initial(bookId);
    }
    return ReadingProgressModel.fromMap(maps.first);
  }

  Future<void> saveProgress(ReadingProgressModel progress) async {
    final db = await _db.database;
    await db.insert(
      'reading_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> resetProgress(String bookId) async {
    final db = await _db.database;
    await db.delete('reading_progress', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
