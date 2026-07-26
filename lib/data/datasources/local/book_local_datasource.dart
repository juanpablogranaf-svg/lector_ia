import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../models/book_model.dart';
import 'database_helper.dart';

/// Data source local para escanear, indexar y recuperar libros del dispositivo.
class BookLocalDatasource {
  final DatabaseHelper _db;

  BookLocalDatasource({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  // ─── Permisos ────────────────────────────────────────────────────────────────

  Future<bool> requestStoragePermission() async {
    // Android 13+ usa READ_MEDIA_*
    if (await _isAndroid13OrAbove()) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<bool> _isAndroid13OrAbove() async {
    // Heurística: si el path /storage/emulated/0 existe, es Android < 13 con acceso legacy
    // En Android 13+ los permisos son granulares. Para lectura de docs usamos MANAGE_EXTERNAL_STORAGE
    // o el picker. Simplificamos a storage permission.
    return false; // Ajustar según versión real en runtime
  }

  // ─── Escaneo de Archivos ─────────────────────────────────────────────────────

  /// Escanea las rutas definidas en [AppConstants.scanPaths] buscando EPUB, PDF y TXT.
  /// Retorna la lista de libros encontrados.
  Stream<BookModel> scanBooks({
    List<String>? customPaths,
    void Function(int found)? onProgress,
  }) async* {
    final paths = customPaths ?? AppConstants.scanPaths;
    int foundCount = 0;

    for (final rootPath in paths) {
      final dir = Directory(rootPath);
      if (!await dir.exists()) continue;

      final stream = dir.list(recursive: true, followLinks: false);
      await for (final entity in stream) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
        if (!AppConstants.supportedExtensions.contains(ext)) continue;

        try {
          final stat = await entity.stat();
          final book = BookModel.fromFile(entity, stat, ext);
          foundCount++;
          onProgress?.call(foundCount);
          yield book;
        } catch (_) {
          // Skip archivos inaccesibles
          continue;
        }
      }
    }
  }

  // ─── CRUD en Base de Datos ───────────────────────────────────────────────────

  Future<List<BookModel>> getAllBooks({String orderBy = 'added_at DESC'}) async {
    final db = await _db.database;
    final maps = await db.query('books', orderBy: orderBy);
    return maps.map(BookModel.fromMap).toList();
  }

  Future<BookModel?> getBookById(String id) async {
    final db = await _db.database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return BookModel.fromMap(maps.first);
  }

  Future<void> insertBook(BookModel book) async {
    final db = await _db.database;
    await db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertBooks(List<BookModel> books) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final book in books) {
      batch.insert('books', book.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateLastOpened(String bookId) async {
    final db = await _db.database;
    await db.update(
      'books',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> deleteBook(String bookId) async {
    final db = await _db.database;
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);
  }

  Future<List<BookModel>> searchBooks(String query) async {
    final db = await _db.database;
    final maps = await db.query(
      'books',
      where: 'title LIKE ? OR author LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'added_at DESC',
    );
    return maps.map(BookModel.fromMap).toList();
  }

  Future<bool> bookExists(String filePath) async {
    final db = await _db.database;
    final id = _generateId(filePath);
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty;
  }

  static String _generateId(String filePath) {
    return filePath.hashCode.abs().toString();
  }
}
