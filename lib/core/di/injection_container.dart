import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/local/book_local_datasource.dart';
import '../../data/datasources/local/progress_local_datasource.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/remote/tts_remote_datasource.dart';
import '../../core/utils/text_chunker.dart';
import '../../core/utils/audio_cache_manager.dart';
import '../../presentation/library/bloc/library_bloc.dart';
import '../../presentation/reader/bloc/reader_bloc.dart';

final GetIt sl = GetIt.instance;

Future<void> init() async {
  // ─── External ────────────────────────────────────────────────────────────────
  debugPrint('🔧 [DI] Obteniendo SharedPreferences...');
  final sharedPrefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(sharedPrefs);
  debugPrint('✅ [DI] SharedPreferences OK.');

  // Inicializar caché de audio
  debugPrint('🔧 [DI] Inicializando AudioCacheManager...');
  await AudioCacheManager.instance.initialize();
  debugPrint('✅ [DI] AudioCacheManager OK.');

  // ─── Core ─────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<Dio>(() => Dio());
  sl.registerLazySingleton<TextChunker>(() => const TextChunker());

  // ─── Data Sources ─────────────────────────────────────────────────────────
  debugPrint('🔧 [DI] Registrando DatabaseHelper...');
  sl.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);

  sl.registerLazySingleton<BookLocalDatasource>(
    () => BookLocalDatasource(db: sl()),
  );

  sl.registerLazySingleton<ProgressLocalDatasource>(
    () => ProgressLocalDatasource(db: sl()),
  );

  sl.registerLazySingleton<TtsRemoteDatasource>(
    () => TtsRemoteDatasource(
      dio: sl(),
      cacheManager: AudioCacheManager.instance,
    ),
  );

  // ─── BLoCs ────────────────────────────────────────────────────────────────
  sl.registerFactory<LibraryBloc>(
    () => LibraryBloc(
      bookDatasource: sl(),
      progressDatasource: sl(),
    ),
  );

  sl.registerFactory<ReaderBloc>(
    () => ReaderBloc(
      bookDatasource: sl(),
      progressDatasource: sl(),
      ttsDatasource: sl(),
      prefs: sl(),
      chunker: sl(),
    ),
  );

  debugPrint('✅ [DI] Todos los servicios registrados.');
}
