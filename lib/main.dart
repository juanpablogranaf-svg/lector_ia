import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_service/audio_service.dart';
import 'app/app.dart';
import 'core/di/injection_container.dart' as di;
import 'services/audio_service/background_audio_handler.dart';
import 'services/audio_service/native_tts_service.dart';

late AudioHandler audioHandler;

void main() {
  // ── 1. Captura global de errores de Flutter (widget tree, rendering, etc.)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🔴 FlutterError: ${details.exceptionAsString()}');
    debugPrint('Stack:\n${details.stack}');
  };

  // ── 2. ErrorWidget.builder: muestra el error en pantalla en lugar de
  //       congelarse en la pantalla de splash / fondo púrpura.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ERROR DE INICIALIZACIÓN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white54, height: 24),
                  Text(
                    details.exceptionAsString(),
                    style: const TextStyle(
                      color: Colors.yellowAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${details.stack ?? "Sin stack trace"}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // ── 3. runZonedGuarded: captura errores async fuera del widget tree
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      debugPrint('🚀 [main] Iniciando LectorIA...');

      // ── Paso 1: Inyección de dependencias (SharedPreferences, sqflite, etc.)
      debugPrint('🚀 [main] Inicializando dependencias (DI)...');
      await di.init().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'di.init() superó 30 segundos. Revisa SharedPreferences o sqflite.',
          );
        },
      );
      debugPrint('✅ [main] DI completada.');

      // ── Paso 1.5: Native TTS Service
      debugPrint('🚀 [main] Inicializando NativeTtsService...');
      await NativeTtsService.instance.init();
      debugPrint('✅ [main] NativeTtsService listo.');

      // ── Paso 2: AudioService (Foreground Service) — con timeout de seguridad
      debugPrint('🚀 [main] Inicializando AudioService...');
      audioHandler = await AudioService.init(
        builder: () => LectorIaAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.lector.ia.audio',
          androidNotificationChannelName: 'LectorIA Audio',
          // 'drawable/ic_notification': vector monocromático blanco/transparente.
          // Android 5+ exige un small icon monocromático en drawable/.
          // 'mipmap/ic_launcher' (ícono de color) causa:
          //   java.lang.IllegalArgumentException: Invalid notification (no valid small icon)
          androidNotificationIcon: 'drawable/ic_notification',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
          notificationColor: Color(0xFF1A1A2E),
          androidStopForegroundOnPause: true,
        ),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException(
            'AudioService.init() superó 20 segundos. '
            'Comprueba el permiso FOREGROUND_SERVICE y el AudioHandler.',
          );
        },
      );
      debugPrint('✅ [main] AudioService listo.');

      // ── Paso 3: Lanzar app
      debugPrint('🚀 [main] Ejecutando runApp...');
      runApp(const LectorIaApp());
      debugPrint('✅ [main] runApp completado.');
    },
    (error, stack) {
      // Errores async no capturados por FlutterError (Dart zone errors)
      debugPrint('🔴 [runZonedGuarded] Error no capturado: $error');
      debugPrint('Stack:\n$stack');

      // Renderiza la pantalla de error directamente si el runApp aún no
      // ha podido ejecutarse (fase de inicialización).
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.red.shade900,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ERROR FATAL DE INICIO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white54, height: 24),
                      Text(
                        error.toString(),
                        style: const TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        stack.toString(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
