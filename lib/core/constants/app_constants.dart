class AppConstants {
  AppConstants._();

  static const String appName = 'LectorIA';
  static const String dbName = 'lector_ia.db';
  static const int dbVersion = 1;

  // Carpetas de usuario que se escanean en busca de libros.
  // ⚠️  NO incluir la raíz '/storage/emulated/0/' porque el escaneo
  //    recursivo entra en Android/data y provoca PermissionDenied en Android 11+.
  static const List<String> scanPaths = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Books',
    '/storage/emulated/0/Libros',
    '/storage/emulated/0/Ebooks',
    '/storage/emulated/0/eBooks',
  ];

  // Segmentos de ruta que siempre se omiten durante el escaneo.
  static const List<String> scanBlockedSegments = [
    '/Android/data',
    '/Android/obb',
    '/Android/media',
    '/.', // directorios ocultos
  ];

  // Extensiones soportadas
  static const List<String> supportedExtensions = ['epub', 'pdf', 'txt'];

  // Chunking
  static const int maxChunkCharacters = 700;
  static const int minChunkCharacters = 100;

  // Caché de audio
  static const int audioCacheMaxMB = 200;
  static const String audioCacheDirName = 'audio_cache';

  // SharedPreferences keys
  static const String prefApiKey = 'tts_api_key';
  static const String prefReaderTheme = 'reader_theme';
  static const String prefFontSize = 'font_size';
  static const String prefFontFamily = 'font_family';
  static const String prefLineHeight = 'line_height';
  static const String prefMargin = 'reader_margin';
  static const String prefTtsSpeed = 'tts_speed';
  static const String prefTtsVoice = 'tts_voice';
  static const String prefTtsVoiceNative = 'tts_voice_native';
  static const String prefTtsProvider = 'tts_provider'; // 'google' o 'native'
  static const String prefThemeMode = 'app_theme_mode';

  // Audio Service
  static const String mediaChannelId = 'com.lector.ia.audio';
  static const String mediaChannelName = 'LectorIA Reproducción';
}
