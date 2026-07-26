import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_chunker.dart';
import '../../../core/utils/audio_cache_manager.dart';
import '../../../data/datasources/local/book_local_datasource.dart';
import '../../../data/datasources/local/progress_local_datasource.dart';
import '../../../data/datasources/remote/tts_remote_datasource.dart';
import '../../../data/models/book_model.dart';
import '../../../data/models/reading_progress_model.dart';
import '../../../services/audio_service/background_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import '../../../main.dart' show audioHandler;

// ─── Events ──────────────────────────────────────────────────────────────────

abstract class ReaderEvent extends Equatable {
  const ReaderEvent();
  @override List<Object?> get props => [];
}

class ReaderBookOpened extends ReaderEvent {
  final String bookId;
  const ReaderBookOpened(this.bookId);
  @override List<Object?> get props => [bookId];
}

class ReaderScrollPositionChanged extends ReaderEvent {
  final double scrollPosition;
  final int characterOffset;
  const ReaderScrollPositionChanged(this.scrollPosition, this.characterOffset);
  @override List<Object?> get props => [scrollPosition, characterOffset];
}

class ReaderThemeChanged extends ReaderEvent {
  final ReaderTheme theme;
  const ReaderThemeChanged(this.theme);
  @override List<Object?> get props => [theme];
}

class ReaderFontSizeChanged extends ReaderEvent {
  final double fontSize;
  const ReaderFontSizeChanged(this.fontSize);
  @override List<Object?> get props => [fontSize];
}

class ReaderTtsPlayToggled extends ReaderEvent {
  const ReaderTtsPlayToggled();
}

class ReaderTtsNextChunk extends ReaderEvent {
  const ReaderTtsNextChunk();
}

class ReaderTtsPrevChunk extends ReaderEvent {
  const ReaderTtsPrevChunk();
}

class ReaderTtsSpeedChanged extends ReaderEvent {
  final double speed;
  const ReaderTtsSpeedChanged(this.speed);
  @override List<Object?> get props => [speed];
}

class ReaderChapterChanged extends ReaderEvent {
  final int chapterIndex;
  const ReaderChapterChanged(this.chapterIndex);
  @override List<Object?> get props => [chapterIndex];
}

class ReaderClosed extends ReaderEvent {
  const ReaderClosed();
}

// ─── State ────────────────────────────────────────────────────────────────────

enum ReaderStatus { initial, loading, loaded, error }
enum TtsStatus { idle, loading, playing, paused, error }

class ReaderState extends Equatable {
  final ReaderStatus status;
  final BookModel? book;
  final String bookContent;
  final ReadingProgressModel? progress;
  final List<TextChunk> chunks;
  final int currentChunkIndex;
  final TtsStatus ttsStatus;
  final String ttsErrorMessage;
  final ReaderTheme readerTheme;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final double ttsSpeed;
  final String? errorMessage;

  const ReaderState({
    this.status = ReaderStatus.initial,
    this.book,
    this.bookContent = '',
    this.progress,
    this.chunks = const [],
    this.currentChunkIndex = 0,
    this.ttsStatus = TtsStatus.idle,
    this.ttsErrorMessage = '',
    this.readerTheme = ReaderTheme.dark,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.margin = 20.0,
    this.ttsSpeed = 1.0,
    this.errorMessage,
  });

  bool get isTtsPlaying => ttsStatus == TtsStatus.playing;
  bool get hasTtsError => ttsStatus == TtsStatus.error;

  TextChunk? get currentChunk =>
      chunks.isNotEmpty && currentChunkIndex < chunks.length
          ? chunks[currentChunkIndex]
          : null;

  ReaderState copyWith({
    ReaderStatus? status,
    BookModel? book,
    String? bookContent,
    ReadingProgressModel? progress,
    List<TextChunk>? chunks,
    int? currentChunkIndex,
    TtsStatus? ttsStatus,
    String? ttsErrorMessage,
    ReaderTheme? readerTheme,
    double? fontSize,
    double? lineHeight,
    double? margin,
    double? ttsSpeed,
    String? errorMessage,
  }) {
    return ReaderState(
      status: status ?? this.status,
      book: book ?? this.book,
      bookContent: bookContent ?? this.bookContent,
      progress: progress ?? this.progress,
      chunks: chunks ?? this.chunks,
      currentChunkIndex: currentChunkIndex ?? this.currentChunkIndex,
      ttsStatus: ttsStatus ?? this.ttsStatus,
      ttsErrorMessage: ttsErrorMessage ?? this.ttsErrorMessage,
      readerTheme: readerTheme ?? this.readerTheme,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status, book, bookContent, progress, chunks, currentChunkIndex,
    ttsStatus, ttsErrorMessage, readerTheme, fontSize, lineHeight,
    margin, ttsSpeed, errorMessage,
  ];
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final BookLocalDatasource _bookDatasource;
  final ProgressLocalDatasource _progressDatasource;
  final TtsRemoteDatasource _ttsDatasource;
  final TextChunker _chunker;
  final SharedPreferences _prefs;

  Timer? _autoSaveTimer;
  StreamSubscription? _chunkIndexSubscription;

  ReaderBloc({
    required BookLocalDatasource bookDatasource,
    required ProgressLocalDatasource progressDatasource,
    required TtsRemoteDatasource ttsDatasource,
    required SharedPreferences prefs,
    TextChunker? chunker,
  })  : _bookDatasource = bookDatasource,
        _progressDatasource = progressDatasource,
        _ttsDatasource = ttsDatasource,
        _prefs = prefs,
        _chunker = chunker ?? const TextChunker(),
        super(const ReaderState()) {
    on<ReaderBookOpened>(_onBookOpened);
    on<ReaderScrollPositionChanged>(_onScrollChanged, transformer: _debounce());
    on<ReaderThemeChanged>(_onThemeChanged);
    on<ReaderFontSizeChanged>(_onFontSizeChanged);
    on<ReaderTtsPlayToggled>(_onTtsPlayToggled);
    on<ReaderTtsNextChunk>(_onNextChunk);
    on<ReaderTtsPrevChunk>(_onPrevChunk);
    on<ReaderTtsSpeedChanged>(_onSpeedChanged);
    on<ReaderChapterChanged>(_onChapterChanged);
    on<ReaderClosed>(_onClosed);

    // Escuchar el índice de chunk desde el AudioHandler
    _chunkIndexSubscription =
        (audioHandler as LectorIaAudioHandler).currentChunkStream.listen((index) {
      if (index != state.currentChunkIndex) {
        emit(state.copyWith(currentChunkIndex: index));
      }
    });

    _loadPreferences();
  }

  // ─── Event Handlers ─────────────────────────────────────────────────────────

  Future<void> _onBookOpened(ReaderBookOpened event, Emitter<ReaderState> emit) async {
    emit(state.copyWith(status: ReaderStatus.loading));
    try {
      final book = await _bookDatasource.getBookById(event.bookId);
      if (book == null) throw Exception('Libro no encontrado');

      final progress = await _progressDatasource.getProgress(event.bookId);

      // Actualizar última apertura
      await _bookDatasource.updateLastOpened(event.bookId);

      // Para TXT: leer contenido directamente
      // Para EPUB/PDF: el visor nativo maneja el contenido
      String content = '';
      if (book.fileType == 'txt') {
        content = await _loadTxtContent(book.filePath);
      }

      // Generar chunks del texto (para TXT; EPUB se carga dinámicamente)
      final chunks = content.isNotEmpty ? _chunker.chunk(content) : <TextChunk>[];

      emit(state.copyWith(
        status: ReaderStatus.loaded,
        book: book,
        bookContent: content,
        progress: progress,
        chunks: chunks,
        currentChunkIndex: progress.chunkIndex,
      ));

      // Pre-cargar primeros 3 chunks si hay API key
      _prefetchNextChunks(book, chunks, progress.chunkIndex);
    } catch (e) {
      emit(state.copyWith(
        status: ReaderStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onScrollChanged(ReaderScrollPositionChanged event, Emitter<ReaderState> emit) async {
    if (state.book == null) return;
    final progress = (state.progress ?? ReadingProgressModel.initial(state.book!.id)).copyWith(
      scrollPosition: event.scrollPosition,
      characterOffset: event.characterOffset,
    );
    emit(state.copyWith(progress: progress));
    await _progressDatasource.saveProgress(progress);
  }

  void _onThemeChanged(ReaderThemeChanged event, Emitter<ReaderState> emit) {
    emit(state.copyWith(readerTheme: event.theme));
    _prefs.setInt(AppConstants.prefReaderTheme, event.theme.index);
  }

  void _onFontSizeChanged(ReaderFontSizeChanged event, Emitter<ReaderState> emit) {
    emit(state.copyWith(fontSize: event.fontSize));
    _prefs.setDouble(AppConstants.prefFontSize, event.fontSize);
  }

  Future<void> _onTtsPlayToggled(ReaderTtsPlayToggled event, Emitter<ReaderState> emit) async {
    if (state.ttsStatus == TtsStatus.playing) {
      await audioHandler.pause();
      emit(state.copyWith(ttsStatus: TtsStatus.paused));
    } else {
      await _startTtsPlayback(emit);
    }
  }

  Future<void> _onNextChunk(ReaderTtsNextChunk event, Emitter<ReaderState> emit) async {
    await audioHandler.skipToNext();
  }

  Future<void> _onPrevChunk(ReaderTtsPrevChunk event, Emitter<ReaderState> emit) async {
    await audioHandler.skipToPrevious();
  }

  void _onSpeedChanged(ReaderTtsSpeedChanged event, Emitter<ReaderState> emit) {
    emit(state.copyWith(ttsSpeed: event.speed));
    audioHandler.setSpeed(event.speed);
    _prefs.setDouble(AppConstants.prefTtsSpeed, event.speed);
  }

  Future<void> _onChapterChanged(ReaderChapterChanged event, Emitter<ReaderState> emit) async {
    if (state.book == null) return;
    final progress = (state.progress ?? ReadingProgressModel.initial(state.book!.id)).copyWith(
      chapterIndex: event.chapterIndex,
      scrollPosition: 0,
      characterOffset: 0,
      chunkIndex: 0,
    );
    await _progressDatasource.saveProgress(progress);
    emit(state.copyWith(progress: progress, currentChunkIndex: 0));
  }

  Future<void> _onClosed(ReaderClosed event, Emitter<ReaderState> emit) async {
    _autoSaveTimer?.cancel();
    // Guardar progreso final
    if (state.progress != null) {
      await _progressDatasource.saveProgress(state.progress!);
    }
    // No detener el audio (continúa en segundo plano)
    emit(const ReaderState());
  }

  // ─── TTS Helpers ─────────────────────────────────────────────────────────────

  Future<void> _startTtsPlayback(Emitter<ReaderState> emit) async {
    if (state.book == null || state.chunks.isEmpty) return;

    final apiKey = _prefs.getString(AppConstants.prefApiKey) ?? '';
    if (apiKey.isEmpty) {
      emit(state.copyWith(
        ttsStatus: TtsStatus.error,
        ttsErrorMessage: 'Configura tu API Key en Ajustes para usar el TTS.',
      ));
      return;
    }

    emit(state.copyWith(ttsStatus: TtsStatus.loading));

    try {
      // Sintetizar el chunk actual
      final chunk = state.chunks[state.currentChunkIndex];
      final result = await _ttsDatasource.synthesizeChunk(
        chunk: chunk,
        bookId: state.book!.id,
        apiKey: apiKey,
        speakingRate: state.ttsSpeed,
      );

      // Cargar cola de chunks restantes en el AudioHandler
      final handler = audioHandler as LectorIaAudioHandler;

      // Sintetizar los próximos 2 chunks para alimentar la cola
      final pathsList = <String>[result.audioFilePath];
      final upcomingChunks = state.chunks
          .skip(state.currentChunkIndex + 1)
          .take(2)
          .toList();

      for (final upcoming in upcomingChunks) {
        try {
          final r = await _ttsDatasource.synthesizeChunk(
            chunk: upcoming,
            bookId: state.book!.id,
            apiKey: apiKey,
            speakingRate: state.ttsSpeed,
          );
          pathsList.add(r.audioFilePath);
        } catch (_) {
          break;
        }
      }

      await handler.loadChapterQueue(
        chunkPaths: pathsList,
        bookTitle: state.book!.title,
        chapterTitle: state.progress != null
            ? 'Capítulo ${state.progress!.chapterIndex + 1}'
            : 'Lectura',
        artUri: null,
        startFromIndex: 0,
      );

      emit(state.copyWith(ttsStatus: TtsStatus.playing));

      // Continuar pre-cargando chunks en background
      _prefetchNextChunks(state.book!, state.chunks, state.currentChunkIndex + 3);
    } catch (e) {
      emit(state.copyWith(
        ttsStatus: TtsStatus.error,
        ttsErrorMessage: e.toString(),
      ));
    }
  }

  Future<void> _prefetchNextChunks(
    BookModel book,
    List<TextChunk> chunks,
    int fromIndex,
  ) async {
    final apiKey = _prefs.getString(AppConstants.prefApiKey) ?? '';
    if (apiKey.isEmpty || chunks.isEmpty) return;

    final toPrefetch = chunks.skip(fromIndex).take(3).toList();
    await _ttsDatasource.prefetchChunks(
      chunks: toPrefetch,
      bookId: book.id,
      apiKey: apiKey,
    );
  }

  Future<String> _loadTxtContent(String filePath) async {
    final file = dart_io.File(filePath);
    return await file.readAsString();
  }

  void _loadPreferences() {
    final themeIndex = _prefs.getInt(AppConstants.prefReaderTheme) ?? ReaderTheme.dark.index;
    final fontSize = _prefs.getDouble(AppConstants.prefFontSize) ?? 18.0;
    final ttsSpeed = _prefs.getDouble(AppConstants.prefTtsSpeed) ?? 1.0;
    emit(state.copyWith(
      readerTheme: ReaderTheme.values[themeIndex],
      fontSize: fontSize,
      ttsSpeed: ttsSpeed,
    ));
  }

  // Debounce para el scroll (guardar cada 500ms)
  EventTransformer<E> _debounce<E>({Duration duration = const Duration(milliseconds: 500)}) {
    return (events, mapper) => events.debounceTime(duration).switchMap(mapper);
  }

  @override
  Future<void> close() async {
    _autoSaveTimer?.cancel();
    _chunkIndexSubscription?.cancel();
    return super.close();
  }
}

// Imports faltantes
import 'dart:io' as dart_io;
import 'package:rxdart/rxdart.dart';
