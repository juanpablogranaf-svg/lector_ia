import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:lector_ia/core/constants/app_constants.dart';

/// Schema y singleton de la base de datos SQLite.
class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _database;

  static DatabaseHelper get instance => _instance ??= DatabaseHelper._();
  DatabaseHelper._();

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _createDb,
      onUpgrade: _upgradeDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT,
        cover_path TEXT,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_size INTEGER,
        total_pages INTEGER,
        total_chapters INTEGER,
        language TEXT,
        added_at INTEGER NOT NULL,
        last_opened_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_progress (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL DEFAULT 0,
        page_number INTEGER NOT NULL DEFAULT 0,
        scroll_position REAL NOT NULL DEFAULT 0.0,
        character_offset INTEGER NOT NULL DEFAULT 0,
        chunk_index INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT,
        file_path TEXT,
        content_start INTEGER,
        content_end INTEGER,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    // Índices para queries frecuentes
    await db.execute('CREATE INDEX idx_books_added ON books(added_at DESC)');
    await db.execute('CREATE INDEX idx_books_opened ON books(last_opened_at DESC)');
    await db.execute('CREATE INDEX idx_progress_book ON reading_progress(book_id)');
    await db.execute('CREATE INDEX idx_chapters_book ON chapters(book_id, chapter_index)');
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    // Migraciones futuras aquí
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
