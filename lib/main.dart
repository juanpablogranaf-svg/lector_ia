import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_service/audio_service.dart';
import 'app/app.dart';
import 'core/di/injection_container.dart' as di;
import 'services/audio_service/background_audio_handler.dart';

late AudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar inyección de dependencias
  await di.init();

  // Inicializar AudioService (Foreground Service)
  audioHandler = await AudioService.init(
    builder: () => LectorIaAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.lector.ia.audio',
      androidNotificationChannelName: 'LectorIA Audio',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_notification',
      androidShowNotificationBadge: true,
      notificationColor: Color(0xFF1A1A2E),
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(const LectorIaApp());
}
