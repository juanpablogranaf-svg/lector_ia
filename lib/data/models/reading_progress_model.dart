class ReadingProgressModel {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int pageNumber;
  final double scrollPosition; // 0.0 a 1.0
  final int characterOffset;   // Posición exacta en el texto
  final int chunkIndex;         // Último chunk TTS escuchado
  final DateTime updatedAt;

  const ReadingProgressModel({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.pageNumber,
    required this.scrollPosition,
    required this.characterOffset,
    required this.chunkIndex,
    required this.updatedAt,
  });

  factory ReadingProgressModel.initial(String bookId) {
    return ReadingProgressModel(
      id: '${bookId}_progress',
      bookId: bookId,
      chapterIndex: 0,
      pageNumber: 0,
      scrollPosition: 0.0,
      characterOffset: 0,
      chunkIndex: 0,
      updatedAt: DateTime.now(),
    );
  }

  factory ReadingProgressModel.fromMap(Map<String, dynamic> map) {
    return ReadingProgressModel(
      id: map['id'] as String,
      bookId: map['book_id'] as String,
      chapterIndex: map['chapter_index'] as int,
      pageNumber: map['page_number'] as int,
      scrollPosition: (map['scroll_position'] as num).toDouble(),
      characterOffset: map['character_offset'] as int,
      chunkIndex: map['chunk_index'] as int,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'page_number': pageNumber,
      'scroll_position': scrollPosition,
      'character_offset': characterOffset,
      'chunk_index': chunkIndex,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  ReadingProgressModel copyWith({
    int? chapterIndex,
    int? pageNumber,
    double? scrollPosition,
    int? characterOffset,
    int? chunkIndex,
  }) {
    return ReadingProgressModel(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      pageNumber: pageNumber ?? this.pageNumber,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      characterOffset: characterOffset ?? this.characterOffset,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      updatedAt: DateTime.now(),
    );
  }

  /// Porcentaje de progreso (0-100) basado en scroll position.
  int get progressPercent => (scrollPosition * 100).round();

  bool get isAtBeginning => scrollPosition < 0.01 && chapterIndex == 0;
}
