import 'dart:io';
import 'package:path/path.dart' as p;

class BookModel {
  final String id;
  final String title;
  final String? author;
  final String? coverPath;
  final String filePath;
  final String fileType; // 'epub', 'pdf', 'txt'
  final int? fileSizeBytes;
  final int? totalPages;
  final int? totalChapters;
  final String? language;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  const BookModel({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    required this.filePath,
    required this.fileType,
    this.fileSizeBytes,
    this.totalPages,
    this.totalChapters,
    this.language,
    required this.addedAt,
    this.lastOpenedAt,
  });

  /// Crea un BookModel desde un archivo del filesystem.
  factory BookModel.fromFile(File file, FileStat stat, String ext) {
    final fileName = p.basenameWithoutExtension(file.path);
    final id = file.path.hashCode.abs().toString();

    // Intentar parsear "Autor - Título" del nombre del archivo
    String title = fileName;
    String? author;
    if (fileName.contains(' - ')) {
      final parts = fileName.split(' - ');
      author = parts.first.trim();
      title = parts.sublist(1).join(' - ').trim();
    }

    return BookModel(
      id: id,
      title: title,
      author: author,
      filePath: file.path,
      fileType: ext,
      fileSizeBytes: stat.size,
      addedAt: stat.modified,
    );
  }

  factory BookModel.fromMap(Map<String, dynamic> map) {
    return BookModel(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String?,
      coverPath: map['cover_path'] as String?,
      filePath: map['file_path'] as String,
      fileType: map['file_type'] as String,
      fileSizeBytes: map['file_size'] as int?,
      totalPages: map['total_pages'] as int?,
      totalChapters: map['total_chapters'] as int?,
      language: map['language'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
      lastOpenedAt: map['last_opened_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_opened_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'cover_path': coverPath,
      'file_path': filePath,
      'file_type': fileType,
      'file_size': fileSizeBytes,
      'total_pages': totalPages,
      'total_chapters': totalChapters,
      'language': language,
      'added_at': addedAt.millisecondsSinceEpoch,
      'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
    };
  }

  BookModel copyWith({
    String? title,
    String? author,
    String? coverPath,
    int? totalPages,
    int? totalChapters,
    String? language,
    DateTime? lastOpenedAt,
  }) {
    return BookModel(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      filePath: filePath,
      fileType: fileType,
      fileSizeBytes: fileSizeBytes,
      totalPages: totalPages ?? this.totalPages,
      totalChapters: totalChapters ?? this.totalChapters,
      language: language ?? this.language,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  String get fileSizeFormatted {
    if (fileSizeBytes == null) return '';
    if (fileSizeBytes! < 1024 * 1024) return '${(fileSizeBytes! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get hasBeenOpened => lastOpenedAt != null;
}
