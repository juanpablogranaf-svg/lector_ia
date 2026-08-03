import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:lector_ia/core/constants/api_constants.dart';
import 'package:lector_ia/core/constants/app_constants.dart';
import 'package:lector_ia/core/errors/failures.dart';
import 'package:lector_ia/core/utils/audio_cache_manager.dart';
import 'package:lector_ia/core/utils/text_chunker.dart';

/// Resultado de una síntesis de audio
class SynthesisResult {
  final String audioFilePath;
  final String chunkHash;
  final bool fromCache;
  final Duration estimatedDuration;

  const SynthesisResult({
    required this.audioFilePath,
    required this.chunkHash,
    required this.fromCache,
    required this.estimatedDuration,
  });
}

/// Cliente para la API de Google Cloud Text-to-Speech.
///
/// Características:
/// - Verifica caché local ANTES de llamar a la API
/// - Rate limiting: máximo 1 solicitud concurrente
/// - Retry automático con exponential backoff (hasta 3 intentos)
/// - Detección automática de idioma con heurística de caracteres
/// - Manejo tipado de errores (429, 403, red, etc.)
class TtsRemoteDatasource {
  final Dio _dio;
  final AudioCacheManager _cacheManager;

  // Rate limiting: semáforo de 1 slot
  bool _requestInProgress = false;
  final _requestQueue = <_PendingRequest>[];

  TtsRemoteDatasource({
    Dio? dio,
    AudioCacheManager? cacheManager,
  })  : _dio = dio ?? _buildDio(),
        _cacheManager = cacheManager ?? AudioCacheManager.instance;

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.ttsBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    // Logging en debug
    assert(() {
      dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
      return true;
    }());

    return dio;
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Sintetiza un [TextChunk] a audio MP3.
  /// Comprueba caché primero; si no está, llama a la API.
  Future<SynthesisResult> synthesizeChunk({
    required TextChunk chunk,
    required String bookId,
    required String apiKey,
    String? languageCode,
    String? voiceName,
    double speakingRate = ApiConstants.defaultSpeakingRate,
  }) async {
    if (apiKey.isEmpty) throw const ApiKeyMissingFailure();

    // 1. Verificar caché
    final cachedPath = await _cacheManager.getCachedAudioPath(chunk.hash);
    if (cachedPath != null) {
      return SynthesisResult(
        audioFilePath: cachedPath,
        chunkHash: chunk.hash,
        fromCache: true,
        estimatedDuration: Duration(milliseconds: (chunk.estimatedDurationSeconds * 1000).round()),
      );
    }

    // 2. Detectar idioma si no se especificó
    final resolvedLanguage = languageCode ?? _detectLanguage(chunk.text);
    final resolvedVoice = voiceName ?? _getVoiceForLanguage(resolvedLanguage);

    // 3. Encolar solicitud (rate limiting)
    final audioBytes = await _enqueueRequest(
      text: chunk.text,
      languageCode: resolvedLanguage,
      voiceName: resolvedVoice,
      speakingRate: speakingRate,
      apiKey: apiKey,
    );

    // 4. Guardar en caché
    final filePath = await _cacheManager.cacheAudio(
      bookId: bookId,
      chunkHash: chunk.hash,
      audioBytes: audioBytes,
    );

    return SynthesisResult(
      audioFilePath: filePath,
      chunkHash: chunk.hash,
      fromCache: false,
      estimatedDuration: Duration(milliseconds: (chunk.estimatedDurationSeconds * 1000).round()),
    );
  }

  /// Pre-carga los próximos N chunks en segundo plano (prefetching).
  Future<void> prefetchChunks({
    required List<TextChunk> chunks,
    required String bookId,
    required String apiKey,
    String? languageCode,
    String? voiceName,
  }) async {
    for (final chunk in chunks) {
      // No bloquear — lanzar en background
      synthesizeChunk(
        chunk: chunk,
        bookId: bookId,
        apiKey: apiKey,
        languageCode: languageCode,
        voiceName: voiceName,
      ).catchError((e) {
        // Errores de prefetch no son fatales
        debugPrint('Prefetch error for chunk ${chunk.index}: $e');
      });
    }
  }

  // ─── Rate Limiting & Queue ───────────────────────────────────────────────────

  Future<List<int>> _enqueueRequest({
    required String text,
    required String languageCode,
    required String voiceName,
    required double speakingRate,
    required String apiKey,
  }) {
    final completer = _PendingRequest(
      text: text,
      languageCode: languageCode,
      voiceName: voiceName,
      speakingRate: speakingRate,
      apiKey: apiKey,
    );
    _requestQueue.add(completer);
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_requestInProgress || _requestQueue.isEmpty) return;
    _requestInProgress = true;
    final request = _requestQueue.removeAt(0);

    _callTtsApi(
      text: request.text,
      languageCode: request.languageCode,
      voiceName: request.voiceName,
      speakingRate: request.speakingRate,
      apiKey: request.apiKey,
    ).then((bytes) {
      request.completer.complete(bytes);
    }).catchError((error) {
      request.completer.completeError(error);
    }).whenComplete(() {
      _requestInProgress = false;
      _processQueue(); // Procesar la siguiente
    });
  }

  // ─── API Call with Retry ────────────────────────────────────────────────────

  Future<List<int>> _callTtsApi({
    required String text,
    required String languageCode,
    required String voiceName,
    required double speakingRate,
    required String apiKey,
    int attempt = 0,
  }) async {
    const maxAttempts = 3;

    final body = {
      'input': {'text': text},
      'voice': {
        'languageCode': languageCode,
        'name': voiceName,
      },
      'audioConfig': {
        'audioEncoding': ApiConstants.audioEncoding,
        'speakingRate': speakingRate,
        'pitch': ApiConstants.defaultPitch,
        'sampleRateHertz': ApiConstants.sampleRateHertz,
        'effectsProfileId': ['headphone-class-device'],
      },
    };

    try {
      final response = await _dio.post(
        ApiConstants.ttsSynthesizeEndpoint,
        queryParameters: {'key': apiKey},
        data: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final audioContent = response.data['audioContent'] as String;
        return base64Decode(audioContent);
      } else {
        throw ServerFailure(
          'Error TTS: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429 && attempt < maxAttempts) {
        // Rate limit — exponential backoff
        final delay = Duration(milliseconds: 500 * pow(2, attempt).toInt());
        await Future.delayed(delay);
        return _callTtsApi(
          text: text,
          languageCode: languageCode,
          voiceName: voiceName,
          speakingRate: speakingRate,
          apiKey: apiKey,
          attempt: attempt + 1,
        );
      } else if (e.response?.statusCode == 403) {
        throw const ServerFailure('API Key inválida o sin permisos para TTS.', statusCode: 403);
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt + 1));
          return _callTtsApi(
            text: text,
            languageCode: languageCode,
            voiceName: voiceName,
            speakingRate: speakingRate,
            apiKey: apiKey,
            attempt: attempt + 1,
          );
        }
        throw const NetworkFailure('Timeout al conectar con la API de TTS.');
      } else {
        throw NetworkFailure(e.message ?? 'Error de red desconocido.');
      }
    }
  }

  // ─── Language Detection ─────────────────────────────────────────────────────

  String _detectLanguage(String text) {
    // Muestra de texto para detección (primeros 300 chars)
    final sample = text.length > 300 ? text.substring(0, 300) : text;

    // Heurística basada en caracteres unicode específicos de cada idioma
    if (_containsSpanish(sample)) return 'es-ES';
    if (_containsFrench(sample)) return 'fr-FR';
    if (_containsGerman(sample)) return 'de-DE';
    if (_containsPortuguese(sample)) return 'pt-BR';
    if (RegExp(r'^[\x00-\x7F]*$').hasMatch(sample)) return 'en-US';

    return ApiConstants.defaultLanguageCode;
  }

  bool _containsSpanish(String text) =>
      RegExp(r'[áéíóúüñ¿¡]', caseSensitive: false).hasMatch(text);

  bool _containsFrench(String text) =>
      RegExp(r'[àâçèêëîïôùûœæ]', caseSensitive: false).hasMatch(text);

  bool _containsGerman(String text) =>
      RegExp(r'[äöüß]', caseSensitive: false).hasMatch(text);

  bool _containsPortuguese(String text) =>
      RegExp(r'[ãõàâêîôûç]', caseSensitive: false).hasMatch(text);

  String _getVoiceForLanguage(String langCode) {
    final prefix = langCode.split('-').first;
    return ApiConstants.langCodeToVoice[prefix] ?? ApiConstants.defaultVoice;
  }
}

// ─── Internal Queue Model ────────────────────────────────────────────────────

class _PendingRequest {
  final String text;
  final String languageCode;
  final String voiceName;
  final double speakingRate;
  final String apiKey;
  final _completerInstance = Completer<List<int>>();

  _PendingRequest({
    required this.text,
    required this.languageCode,
    required this.voiceName,
    required this.speakingRate,
    required this.apiKey,
  });

  Future<List<int>> get future => _completerInstance.future;
  Completer<List<int>> get completer => _completerInstance;
}

