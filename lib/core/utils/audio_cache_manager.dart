import 'dart:io';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

/// Entrada en el cache LRU
class _CacheEntry {
  final String hash;
  final String filePath;
  final int sizeBytes;
  DateTime lastAccessed;

  _CacheEntry({
    required this.hash,
    required this.filePath,
    required this.sizeBytes,
    required this.lastAccessed,
  });
}

/// Gestiona el caché local de audio MP3 generado por TTS.
///
/// - Almacena archivos con nombre: `{bookId}_{chunkHash}.mp3`
/// - Política LRU (Least Recently Used) con límite de 200MB
/// - Thread-safe mediante Dart's single-threaded async model
class AudioCacheManager {
  static AudioCacheManager? _instance;
  static AudioCacheManager get instance => _instance ??= AudioCacheManager._();
  AudioCacheManager._();

  Directory? _cacheDir;
  final _lruCache = LinkedHashMap<String, _CacheEntry>();
  int _totalSizeBytes = 0;
  static const int _maxSizeBytes = AppConstants.audioCacheMaxMB * 1024 * 1024;

  bool _initialized = false;

  // ─── Initialization ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    final appCache = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appCache.path}/${AppConstants.audioCacheDirName}');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    await _loadExistingEntries();
    _initialized = true;
  }

  Future<void> _loadExistingEntries() async {
    final files = _cacheDir!.listSync().whereType<File>().toList();
    for (final file in files) {
      final stat = await file.stat();
      final name = file.uri.pathSegments.last;
      // Formato: {bookId}_{hash}.mp3
      final hashPart = name.replaceAll('.mp3', '').split('_').last;
      final entry = _CacheEntry(
        hash: hashPart,
        filePath: file.path,
        sizeBytes: stat.size,
        lastAccessed: stat.accessed,
      );
      _lruCache[hashPart] = entry;
      _totalSizeBytes += stat.size;
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Retorna la ruta del archivo cacheado, o null si no existe.
  Future<String?> getCachedAudioPath(String chunkHash) async {
    await _ensureInitialized();
    final entry = _lruCache[chunkHash];
    if (entry == null) return null;

    final file = File(entry.filePath);
    if (!await file.exists()) {
      _lruCache.remove(chunkHash);
      _totalSizeBytes -= entry.sizeBytes;
      return null;
    }

    // Actualizar acceso (LRU)
    entry.lastAccessed = DateTime.now();
    _lruCache.remove(chunkHash);
    _lruCache[chunkHash] = entry;

    return entry.filePath;
  }

  /// Guarda bytes de audio MP3 en el caché.
  /// Retorna la ruta del archivo guardado.
  Future<String> cacheAudio({
    required String bookId,
    required String chunkHash,
    required List<int> audioBytes,
  }) async {
    await _ensureInitialized();

    // Verificar si ya existe
    final existing = await getCachedAudioPath(chunkHash);
    if (existing != null) return existing;

    final fileName = '${bookId}_$chunkHash.mp3';
    final filePath = '${_cacheDir!.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(audioBytes);

    final entry = _CacheEntry(
      hash: chunkHash,
      filePath: filePath,
      sizeBytes: audioBytes.length,
      lastAccessed: DateTime.now(),
    );
    _lruCache[chunkHash] = entry;
    _totalSizeBytes += audioBytes.length;

    // Evicción si superamos el límite
    await _evictIfNeeded();

    return filePath;
  }

  /// Elimina todo el caché de un libro específico.
  Future<void> clearBookCache(String bookId) async {
    await _ensureInitialized();
    final toRemove = <String>[];

    for (final entry in _lruCache.values) {
      if (entry.filePath.contains('${bookId}_')) {
        final file = File(entry.filePath);
        if (await file.exists()) await file.delete();
        toRemove.add(entry.hash);
        _totalSizeBytes -= entry.sizeBytes;
      }
    }
    for (final hash in toRemove) {
      _lruCache.remove(hash);
    }
  }

  /// Elimina todo el caché de audio.
  Future<void> clearAll() async {
    await _ensureInitialized();
    final files = _cacheDir!.listSync().whereType<File>();
    for (final file in files) {
      await file.delete();
    }
    _lruCache.clear();
    _totalSizeBytes = 0;
  }

  /// Tamaño actual del caché en MB.
  double get currentSizeMB => _totalSizeBytes / (1024 * 1024);

  /// Número de chunks cacheados.
  int get cachedChunksCount => _lruCache.length;

  // ─── Private Methods ────────────────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  Future<void> _evictIfNeeded() async {
    while (_totalSizeBytes > _maxSizeBytes && _lruCache.isNotEmpty) {
      // Eliminar el menos recientemente usado (primero en LinkedHashMap)
      final lruKey = _lruCache.keys.first;
      final lruEntry = _lruCache.remove(lruKey)!;
      final file = File(lruEntry.filePath);
      if (await file.exists()) await file.delete();
      _totalSizeBytes -= lruEntry.sizeBytes;
    }
  }
}
