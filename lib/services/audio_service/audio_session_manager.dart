import 'dart:async';
import 'package:audio_session/audio_session.dart';

/// Gestiona el Audio Focus de Android.
///
/// Responsabilidades:
/// - Solicitar/abandonar el Audio Focus antes/después de reproducir
/// - Pausar automáticamente si entra una llamada telefónica
/// - Pausar si otro app toma el foco (música, video)
/// - Hacer "duck" (bajar volumen) en notificaciones breves
/// - Reanudar tras perder el foco transitoriamente
class AudioSessionManager {
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<bool>? _becomingNoisySubscription;

  // Callbacks para notificar al handler
  VoidCallback? onPause;
  VoidCallback? onResume;
  VoidCallback? onDuck;   // Bajar volumen
  VoidCallback? onUnduck; // Restaurar volumen

  bool _wasDucked = false;
  bool _wasInterrupted = false;

  // ─── Initialization ─────────────────────────────────────────────────────────

  Future<void> init({
    VoidCallback? onPause,
    VoidCallback? onResume,
    VoidCallback? onDuck,
    VoidCallback? onUnduck,
  }) async {
    this.onPause = onPause;
    this.onResume = onResume;
    this.onDuck = onDuck;
    this.onUnduck = onUnduck;

    _session = await AudioSession.instance;

    await _session!.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false, // Nosotros controlamos el duck
    ));

    _listenToInterruptions();
    _listenToBecomingNoisy();
  }

  // ─── Audio Focus ─────────────────────────────────────────────────────────────

  /// Solicita Audio Focus. Retorna true si fue concedido.
  Future<bool> requestAudioFocus() async {
    if (_session == null) await init();
    return await _session!.setActive(true);
  }

  /// Abandona el Audio Focus (al pausar o detener).
  Future<void> abandonAudioFocus() async {
    await _session?.setActive(false);
  }

  // ─── Interruption Handling ───────────────────────────────────────────────────

  void _listenToInterruptions() {
    _interruptionSubscription = _session!.interruptionEventStream.listen((event) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Notificación breve (ej. GPS, asistente)
          _wasDucked = true;
          onDuck?.call();
          break;

        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // Llamada telefónica, otra app toma el foco
          if (event.begin) {
            _wasInterrupted = true;
            onPause?.call();
          } else {
            // Interrupción terminó
            if (_wasDucked) {
              _wasDucked = false;
              onUnduck?.call();
            } else if (_wasInterrupted) {
              _wasInterrupted = false;
              // Solo reanudar automáticamente si la interrupción fue breve
              onResume?.call();
            }
          }
          break;
      }
    });
  }

  /// "Becoming Noisy": cuando el usuario desenchufa los auriculares,
  /// pausar automáticamente para evitar reproducción por el altavoz.
  void _listenToBecomingNoisy() {
    _becomingNoisySubscription = _session!.becomingNoisyEventStream.listen((_) {
      onPause?.call();
    });
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  void dispose() {
    _interruptionSubscription?.cancel();
    _becomingNoisySubscription?.cancel();
    _session?.setActive(false);
  }
}

typedef VoidCallback = void Function();
