import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

class NativeTtsService {
  NativeTtsService._();
  static final NativeTtsService instance = NativeTtsService._();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  
  // Callback para cuando se termina de hablar
  void Function()? _onCompletion;

  Future<void> init() async {
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _onCompletion?.call();
    });
    
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
    });

    _flutterTts.setCancelHandler(() {
      _isSpeaking = false;
    });
  }

  /// Sintetiza texto directamente a un archivo de audio local (offline) y retorna la ruta.
  /// Esto nos permite reutilizar el LectorIaAudioHandler (just_audio) y toda la lógica de segundo plano,
  /// incluyendo el Media Session, controles en bloqueo, skip, etc.
  Future<String> synthesizeToFile({
    required String text,
    required String bookId,
    required String chunkHash,
    required String voiceName,
    required double rate,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final nativeTtsDir = Directory('${tempDir.path}/native_tts_cache');
    if (!await nativeTtsDir.exists()) {
      await nativeTtsDir.create(recursive: true);
    }

    final filePath = '${nativeTtsDir.path}/${bookId}_$chunkHash.wav';
    final file = File(filePath);
    
    // Si ya existe sintetizado localmente, devolver la ruta
    if (await file.exists()) {
      return filePath;
    }

    // Configurar voz y velocidad
    if (voiceName.isNotEmpty) {
      await _flutterTts.setVoice({"name": voiceName, "locale": "es-ES"}); // locale aproximado
    }
    
    // Convertir el rate de just_audio (0.5 a 2.0) al de flutter_tts (normalmente 0.0 a 1.0)
    final nativeRate = (rate / 2.0).clamp(0.0, 1.0);
    await _flutterTts.setSpeechRate(nativeRate);

    // Sintetizar a archivo nativamente
    // En Android, synthesizeToFile escribe un archivo de audio en la ruta dada.
    // Nota: en algunos dispositivos Android, el nombre debe terminar en .wav o .mp3.
    final result = await _flutterTts.synthesizeToFile(text, Platform.isAndroid ? '${bookId}_$chunkHash.wav' : filePath);
    
    if (Platform.isAndroid) {
      // En Android, synthesizeToFile a veces guarda en la carpeta externa de descargas de la app
      // o directamente en la ruta especificada de forma interna según la versión de flutter_tts.
      // Si el archivo no aparece en la ruta absoluta directamente, flutter_tts lo coloca en el
      // directorio de archivos externos de la app. Para evitar líos y asegurar portabilidad,
      // podemos esperar un momento a que se complete la escritura.
      
      // La API synthesizeToFile en Android genera el archivo en:
      // Context.getExternalFilesDir(null) + "/" + nombre del archivo
      final externalDir = await getExternalStorageDirectory();
      final androidFilePath = '${externalDir?.path}/${bookId}_$chunkHash.wav';
      final androidFile = File(androidFilePath);

      // Esperar brevemente a que aparezca el archivo sintetizado
      int retries = 0;
      while (!await androidFile.exists() && retries < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }

      if (await androidFile.exists()) {
        return androidFilePath;
      }
    }

    int retries = 0;
    while (!await file.exists() && retries < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }

    if (await file.exists()) {
      return filePath;
    }

    // Si fallase la síntesis a archivo, reproducimos directamente por altavoz nativo como fallback
    throw Exception('No se pudo escribir el archivo de audio nativo. ¿Permisos de almacenamiento concedidos?');
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }
}
