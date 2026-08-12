import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/datasources/local/book_local_datasource.dart';
import '../../../data/datasources/local/progress_local_datasource.dart';
import '../../../data/models/book_model.dart';
import '../../../data/models/reading_progress_model.dart';
import '../../../core/theme/app_theme.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();
  @override List<Object?> get props => [];
}

class LibraryScanStarted extends LibraryEvent {
  const LibraryScanStarted();
}

class LibrarySearchChanged extends LibraryEvent {
  final String query;
  const LibrarySearchChanged(this.query);
  @override List<Object?> get props => [query];
}

class LibraryThemeToggled extends LibraryEvent {
  const LibraryThemeToggled();
}

class LibraryBookDeleted extends LibraryEvent {
  final String bookId;
  const LibraryBookDeleted(this.bookId);
  @override List<Object?> get props => [bookId];
}

class LibrarySortChanged extends LibraryEvent {
  final LibrarySortBy sortBy;
  const LibrarySortChanged(this.sortBy);
  @override List<Object?> get props => [sortBy];
}

class LibraryBookImported extends LibraryEvent {
  final BookModel book;
  const LibraryBookImported(this.book);
  @override List<Object?> get props => [book];
}

enum LibrarySortBy { recentlyAdded, lastOpened, title, author }

// ─── State ────────────────────────────────────────────────────────────────────

enum LibraryStatus { initial, scanning, loaded, error }

class LibraryState extends Equatable {
  final LibraryStatus status;
  final List<BookModel> books;
  final List<BookModel> filteredBooks;
  final Map<String, ReadingProgressModel> progressMap;
  final String searchQuery;
  final ThemeMode themeMode;
  final LibrarySortBy sortBy;
  final int scanProgress;
  final String? errorMessage;

  const LibraryState({
    this.status = LibraryStatus.initial,
    this.books = const [],
    this.filteredBooks = const [],
    this.progressMap = const {},
    this.searchQuery = '',
    this.themeMode = ThemeMode.dark,
    this.sortBy = LibrarySortBy.recentlyAdded,
    this.scanProgress = 0,
    this.errorMessage,
  });

  LibraryState copyWith({
    LibraryStatus? status,
    List<BookModel>? books,
    List<BookModel>? filteredBooks,
    Map<String, ReadingProgressModel>? progressMap,
    String? searchQuery,
    ThemeMode? themeMode,
    LibrarySortBy? sortBy,
    int? scanProgress,
    String? errorMessage,
  }) {
    return LibraryState(
      status: status ?? this.status,
      books: books ?? this.books,
      filteredBooks: filteredBooks ?? this.filteredBooks,
      progressMap: progressMap ?? this.progressMap,
      searchQuery: searchQuery ?? this.searchQuery,
      themeMode: themeMode ?? this.themeMode,
      sortBy: sortBy ?? this.sortBy,
      scanProgress: scanProgress ?? this.scanProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status, books, filteredBooks, progressMap, searchQuery,
    themeMode, sortBy, scanProgress, errorMessage,
  ];
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final BookLocalDatasource _bookDatasource;
  final ProgressLocalDatasource _progressDatasource;

  LibraryBloc({
    required BookLocalDatasource bookDatasource,
    required ProgressLocalDatasource progressDatasource,
  })  : _bookDatasource = bookDatasource,
        _progressDatasource = progressDatasource,
        super(const LibraryState()) {
    on<LibraryScanStarted>(_onScanStarted);
    on<LibrarySearchChanged>(_onSearchChanged);
    on<LibraryThemeToggled>(_onThemeToggled);
    on<LibraryBookDeleted>(_onBookDeleted);
    on<LibrarySortChanged>(_onSortChanged);
    on<LibraryBookImported>(_onBookImported);
  }

  Future<void> _onScanStarted(LibraryScanStarted event, Emitter<LibraryState> emit) async {
    emit(state.copyWith(status: LibraryStatus.scanning));

    try {
      // Solicitar permisos en tiempo de ejecución
      final hasPermission = await _bookDatasource.requestStoragePermission();
      if (!hasPermission) {
        emit(state.copyWith(
          status: LibraryStatus.error,
          errorMessage: 'Permiso de almacenamiento denegado. Concede el acceso para escanear libros.',
        ));
        return;
      }

      final existingBooks = await _bookDatasource.getAllBooks();
      emit(state.copyWith(books: existingBooks, filteredBooks: existingBooks));

      // Escanear nuevos libros en el dispositivo
      final newBooks = <BookModel>[];
      int count = 0;

      await for (final book in _bookDatasource.scanBooks(
        onProgress: (n) => count = n,
      )) {
        final exists = await _bookDatasource.bookExists(book.filePath);
        if (!exists) {
          await _bookDatasource.insertBook(book);
          newBooks.add(book);
        }
        emit(state.copyWith(scanProgress: count));
      }

      final allBooks = await _bookDatasource.getAllBooks();
      final progressMap = <String, ReadingProgressModel>{};
      for (final book in allBooks) {
        progressMap[book.id] = await _progressDatasource.getProgress(book.id);
      }

      emit(state.copyWith(
        status: LibraryStatus.loaded,
        books: allBooks,
        filteredBooks: _applySort(allBooks, state.sortBy),
        progressMap: progressMap,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: LibraryStatus.error,
        errorMessage: 'Error al escanear: ${e.toString()}',
      ));
    }
  }

  void _onSearchChanged(LibrarySearchChanged event, Emitter<LibraryState> emit) {
    final query = event.query.toLowerCase().trim();
    final filtered = query.isEmpty
        ? state.books
        : state.books.where((b) {
            return b.title.toLowerCase().contains(query) ||
                (b.author?.toLowerCase().contains(query) ?? false);
          }).toList();

    emit(state.copyWith(
      searchQuery: event.query,
      filteredBooks: _applySort(filtered, state.sortBy),
    ));
  }

  void _onThemeToggled(LibraryThemeToggled event, Emitter<LibraryState> emit) {
    final newMode = state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    emit(state.copyWith(themeMode: newMode));
  }

  Future<void> _onBookDeleted(LibraryBookDeleted event, Emitter<LibraryState> emit) async {
    await _bookDatasource.deleteBook(event.bookId);
    final updated = state.books.where((b) => b.id != event.bookId).toList();
    emit(state.copyWith(
      books: updated,
      filteredBooks: _applySort(
        state.filteredBooks.where((b) => b.id != event.bookId).toList(),
        state.sortBy,
      ),
    ));
  }

  void _onSortChanged(LibrarySortChanged event, Emitter<LibraryState> emit) {
    emit(state.copyWith(
      sortBy: event.sortBy,
      filteredBooks: _applySort(state.filteredBooks, event.sortBy),
    ));
  }

  Future<void> _onBookImported(LibraryBookImported event, Emitter<LibraryState> emit) async {
    try {
      final exists = await _bookDatasource.bookExists(event.book.filePath);
      if (!exists) {
        await _bookDatasource.insertBook(event.book);
      }
      final allBooks = await _bookDatasource.getAllBooks();
      final progressMap = Map<String, ReadingProgressModel>.from(state.progressMap);
      if (!progressMap.containsKey(event.book.id)) {
        progressMap[event.book.id] = await _progressDatasource.getProgress(event.book.id);
      }
      emit(state.copyWith(
        books: allBooks,
        filteredBooks: _applySort(allBooks, state.sortBy),
        progressMap: progressMap,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: LibraryStatus.error,
        errorMessage: 'Error al importar libro: ${e.toString()}',
      ));
    }
  }

  List<BookModel> _applySort(List<BookModel> books, LibrarySortBy sortBy) {
    final sorted = List<BookModel>.from(books);
    switch (sortBy) {
      case LibrarySortBy.recentlyAdded:
        sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case LibrarySortBy.lastOpened:
        sorted.sort((a, b) {
          if (a.lastOpenedAt == null && b.lastOpenedAt == null) return 0;
          if (a.lastOpenedAt == null) return 1;
          if (b.lastOpenedAt == null) return -1;
          return b.lastOpenedAt!.compareTo(a.lastOpenedAt!);
        });
        break;
      case LibrarySortBy.title:
        sorted.sort((a, b) => a.title.compareTo(b.title));
        break;
      case LibrarySortBy.author:
        sorted.sort((a, b) => (a.author ?? '').compareTo(b.author ?? ''));
        break;
    }
    return sorted;
  }
}
