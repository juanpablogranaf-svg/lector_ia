import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class NativeTtsService {
  NativeTtsService._();
  static final NativeTtsService instance = NativeTtsService._();

  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    _flutterTts.setCompletionHandler(() {
      debugPrint('[NativeTTS] Completion');
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('[NativeTTS] Error: $msg');
    });

    _flutterTts.setCancelHandler(() {
      debugPrint('[NativeTTS] Cancelled');
    });

    _initialized = true;
    debugPrint('[NativeTTS] Initialized');
  }

  /// Verifica si el idioma [languageCode] está disponible en el motor TTS del dispositivo.
  /// Lanza [NativeTtsLanguageUnavailableException] si no lo está.
  Future<void> _configureLanguage(String languageCode) async {
    try {
      final result = await _flutterTts.setLanguage(languageCode);
      // flutter_tts devuelve 1 si OK, 0 si no disponible
      if (result == 0) {
        throw NativeTtsLanguageUnavailableException(
          'El motor TTS del dispositivo no tiene instalado el idioma "$languageCode". '
          'Ve a Ajustes del teléfono → Accesibilidad → TTS → e instala el paquete de español.',
        );
      }
      debugPrint('[NativeTTS] Language set: $languageCode (result=$result)');
    } catch (e) {
      if (e is NativeTtsLanguageUnavailableException) rethrow;
      // Si la excepción es del propio flutter_tts (ej. PlatformException), la propagamos con contexto
      throw NativeTtsLanguageUnavailableException(
        'No se pudo configurar el idioma TTS "$languageCode": $e',
      );
    }
  }

  /// Sintetiza [text] directamente a un archivo de audio local (offline) y retorna la ruta absoluta.
  /// Usa el motor TTS nativo de Android/iOS para generar audio sin conexión.
  Future<String> synthesizeToFile({
    required String text,
    required String bookId,
    required String chunkHash,
    String voiceName = '',
    String languageCode = 'es-ES',
    double rate = 1.0,
  }) async {
    if (!_initialized) await init();

    final tempDir = await getTemporaryDirectory();
    final nativeTtsDir = Directory('${tempDir.path}/native_tts_cache');
    if (!await nativeTtsDir.exists()) {
      await nativeTtsDir.create(recursive: true);
    }

    // Nombre de archivo seguro (sin caracteres especiales)
    final safeBookId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = '${safeBookId}_$chunkHash.wav';
    final filePath = '${nativeTtsDir.path}/$fileName';
    final file = File(filePath);

    // Si ya existe en caché, reutilizar
    if (await file.exists() && await file.length() > 100) {
      debugPrint('[NativeTTS] Cache hit: $filePath');
      return filePath;
    }

    // 1. Configurar idioma (obligatorio antes de sintetizar en Android)
    await _configureLanguage(languageCode);

    // 2. Configurar voz específica si se proporcionó
    if (voiceName.isNotEmpty) {
      try {
        await _flutterTts.setVoice({'name': voiceName, 'locale': languageCode});
        debugPrint('[NativeTTS] Voice set: $voiceName');
      } catch (e) {
        // Voz específica no disponible — continuar con la voz por defecto del idioma
        debugPrint('[NativeTTS] Voice "$voiceName" not available, using default: $e');
      }
    }

    // 3. Configurar velocidad (flutter_tts usa rango 0.0–1.0, just_audio usa 0.5–2.0)
    final nativeRate = (rate / 2.0).clamp(0.1, 1.0);
    await _flutterTts.setSpeechRate(nativeRate);

    // 4. Sanitizar el texto antes de sintetizarlo
    // Limpieza esencial para el motor TTS nativo: elimina caracteres especiales,
    // nulos y saltos de línea que pueden romper la síntesis en ciertos dispositivos
    final sanitizedText = text
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\x00', '')                          // Bytes nulos
        .replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]'), '') // Caracteres de control
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    if (sanitizedText.isEmpty) {
      throw NativeTtsSynthesisException('El texto a sintetizar está vacío después de la sanitización.');
    }

    // Truncar a 4000 caracteres si el texto es muy largo (límite seguro para el motor nativo)
    final truncatedText = sanitizedText.length > 4000 
        ? sanitizedText.substring(0, 4000)
        : sanitizedText;

    // 5. Sintetizar a archivo con manejo de completado asíncrono
    final completer = Completer<String>();
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete('completed');
    });
    debugPrint('[NativeTTS] Synthesizing filename: $fileName (${truncatedText.length} chars)');
    final result = await _flutterTts.synthesizeToFile(truncatedText, fileName);
    // Esperar a que el motor indique completado
    await completer.future;

    // 5. Esperar a que el archivo esté disponible en el directorio externo de la app (máx 5 segundos)
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      final externalFile = File('${externalDir.path}/$fileName');
      int retries = 0;
      while (retries < 50) {
        if (await externalFile.exists() && await externalFile.length() > 100) {
          debugPrint('[NativeTTS] File ready in external: ${externalFile.path} (${await externalFile.length()} bytes)');
          // Copiar al cache temporal interno por consistencia
          final copied = await externalFile.copy(filePath);
          return copied.path;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }
    }

    // 6. Fallback final: verificar en tempDir directo si se creó ahí por compatibilidad
    if (await file.exists() && await file.length() > 100) {
      debugPrint('[NativeTTS] File ready in temp fallback: $filePath (${await file.length()} bytes)');
      return filePath;
    }

    throw NativeTtsSynthesisException(
      'No se generó el archivo de audio TTS nativo.\n'
      'Verifica que el motor TTS del dispositivo tenga el idioma español instalado.\n'
      'Ruta buscada: ${externalDir?.path}/$fileName\n'
      'Resultado de síntesis: $result',
    );
  }

  /// Lista las voces disponibles en el motor TTS del dispositivo para el idioma dado.
  Future<List<Map<String, String>>> getAvailableVoices({String languageCode = 'es-ES'}) async {
    if (!_initialized) await init();
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return [];
      return (voices as List)
          .cast<Map>()
          .where((v) => (v['locale'] as String? ?? '').startsWith(languageCode.split('-').first))
          .map((v) => {'name': v['name'] as String, 'locale': v['locale'] as String})
          .toList();
    } catch (e) {
      debugPrint('[NativeTTS] getAvailableVoices error: $e');
      return [];
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    debugPrint('[NativeTTS] Stopped');
  }
}

/// Excepción lanzada cuando el idioma no está instalado en el motor TTS del dispositivo.
class NativeTtsLanguageUnavailableException implements Exception {
  final String message;
  const NativeTtsLanguageUnavailableException(this.message);
  @override
  String toString() => message;
}

/// Excepción lanzada cuando la síntesis a archivo falla.
class NativeTtsSynthesisException implements Exception {
  final String message;
  const NativeTtsSynthesisException(this.message);
  @override
  String toString() => message;
}
