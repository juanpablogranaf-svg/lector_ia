import 'dart:io';
import 'package:flutter/foundation.dart';
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
    // Para Android 11+ (API 30+) requerimos MANAGE_EXTERNAL_STORAGE para indexación completa.
    // Usamos Permission.manageExternalStorage.
    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }
    // Backup para versiones anteriores o si no se concede pero se concedió el clásico
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  // ─── Escaneo de Archivos ─────────────────────────────────────────────────────

  /// Escanea las rutas definidas en [AppConstants.scanPaths] buscando EPUB, PDF y TXT.
  ///
  /// Usa exploración iterativa (BFS) directorio a directorio con try-catch
  /// individual, de modo que un directorio con PermissionDenied no rompe
  /// el escaneo completo (problema típico de Scoped Storage en Android 11+).
  Stream<BookModel> scanBooks({
    List<String>? customPaths,
    void Function(int found)? onProgress,
  }) async* {
    final paths = customPaths ?? AppConstants.scanPaths;
    int foundCount = 0;

    for (final rootPath in paths) {
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) continue;

      // BFS: cola de directorios pendientes de explorar
      final queue = <Directory>[rootDir];

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);

        // ── Comprobar si el directorio está bloqueado ───────────────────────
        final path = current.path;
        bool isBlocked = false;
        for (final segment in AppConstants.scanBlockedSegments) {
          if (path.contains(segment)) {
            isBlocked = true;
            break;
          }
        }
        if (isBlocked) {
          debugPrint('🚫 [Scanner] Omitiendo ruta restringida: $path');
          continue;
        }

        // ── Listar contenido del directorio con try-catch individual ────────
        List<FileSystemEntity> entities;
        try {
          entities = current.listSync(followLinks: false);
        } on FileSystemException catch (e) {
          debugPrint('⚠️ [Scanner] Sin acceso a: $path — ${e.message}');
          continue;
        } catch (e) {
          debugPrint('⚠️ [Scanner] Error inesperado en: $path — $e');
          continue;
        }

        for (final entity in entities) {
          if (entity is Directory) {
            queue.add(entity);
          } else if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '').trim();
            if (!AppConstants.supportedExtensions.contains(ext)) continue;

            try {
              final stat = await entity.stat();
              final book = BookModel.fromFile(entity, stat, ext);
              foundCount++;
              onProgress?.call(foundCount);
              yield book;
            } catch (_) {
              // Archivo inaccesible — ignorar y continuar
            }
          }
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
