import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_session_manager.dart';

/// Handler del servicio de audio en segundo plano.
///
/// Implementa [AudioHandler] de `audio_service`, lo que en Android genera
/// automáticamente un Foreground Service con notificación multimedia
/// y controles en la pantalla de bloqueo.
///
/// Controles expuestos:
///   ▶ Play | ⏸ Pause | ⏭ Siguiente párrafo | ⏮ Párrafo anterior | ⏹ Stop
class LectorIaAudioHandler extends BaseAudioHandler with QueueHandler {
  final AudioPlayer _player = AudioPlayer();
  final AudioSessionManager _sessionManager = AudioSessionManager();

  // Queue de rutas de audio (chunks MP3 del capítulo actual)
  final List<String> _chunkPaths = [];
  int _currentChunkIndex = 0;

  // Stream para notificar al UI el índice del chunk actual
  final _currentChunkStreamController = StreamController<int>.broadcast();
  Stream<int> get currentChunkStream => _currentChunkStreamController.stream;

  // ─── Subscripciones gestionadas (evita "addStream while addStream") ──────────

  /// Suscripción al stream de eventos del player → propaga a playbackState.
  /// Se usa .add() manual en lugar de .pipe() / addStream() para no bloquear
  /// el BehaviorSubject de audio_service.
  StreamSubscription<PlaybackState>? _playbackEventSub;

  /// Suscripción al stream de estado del player → auto-avance de chunks.
  StreamSubscription<PlayerState>? _playerStateSub;

  // ─── Constructor ─────────────────────────────────────────────────────────────

  LectorIaAudioHandler() {
    _initPlayer();
    _sessionManager.init();
  }

  void _initPlayer() {
    _attachPlayerListeners();
  }

  /// Conecta las suscripciones al player.
  /// Cancelar antes de volver a llamar con [_detachPlayerListeners].
  void _attachPlayerListeners() {
    // Propagar eventos del player a playbackState usando .add() (NO .pipe())
    _playbackEventSub = _player.playbackEventStream
        .map(_transformEvent)
        .listen((state) {
      // Sólo emite si el subject no está ya cerrado
      if (!playbackState.isClosed) {
        playbackState.add(state);
      }
    });

    // Auto-avanzar al siguiente chunk cuando termina el actual
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onChunkCompleted();
      }
    });
  }

  /// Cancela y elimina las suscripciones activas al player.
  Future<void> _detachPlayerListeners() async {
    await _playbackEventSub?.cancel();
    _playbackEventSub = null;
    await _playerStateSub?.cancel();
    _playerStateSub = null;
  }

  // ─── Queue Management (Public API llamada desde el ReaderBloc) ───────────────

  /// Carga la cola de chunks de audio para el capítulo actual.
  Future<void> loadChapterQueue({
    required List<String> chunkPaths,
    required String bookTitle,
    required String chapterTitle,
    required Uri? artUri,
    int startFromIndex = 0,
  }) async {
    // Detener reproducción y cancelar suscripciones antes de cargar nueva cola
    await _detachPlayerListeners();
    await _player.stop();

    _chunkPaths
      ..clear()
      ..addAll(chunkPaths);
    _currentChunkIndex = startFromIndex.clamp(0, chunkPaths.length - 1);

    // Actualizar MediaItem (visible en notificación y pantalla de bloqueo)
    mediaItem.add(MediaItem(
      id: chunkPaths[_currentChunkIndex],
      title: bookTitle,
      artist: chapterTitle,
      artUri: artUri ?? Uri.parse('asset:///assets/icons/book_cover_default.png'),
      duration: null, // Calculado al reproducir
    ));

    // Actualizar la queue visible
    final items = List.generate(
      chunkPaths.length,
      (i) => MediaItem(
        id: chunkPaths[i],
        title: 'Fragmento ${i + 1}',
        artist: chapterTitle,
      ),
    );
    queue.add(items);

    // Volver a conectar listeners antes de reproducir
    _attachPlayerListeners();

    await _playCurrentChunk();
  }

  /// Carga un chunk individual y lo reproduce (para modo single-chunk).
  Future<void> loadAndPlayChunk(String audioFilePath) async {
    await _detachPlayerListeners();
    await _player.stop();
    _attachPlayerListeners();

    await _player.setFilePath(audioFilePath);
    await _player.play();
  }

  // ─── AudioHandler Overrides ──────────────────────────────────────────────────

  @override
  Future<void> play() async {
    await _sessionManager.requestAudioFocus();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _sessionManager.abandonAudioFocus();
  }

  @override
  Future<void> stop() async {
    // 1. Cancelar suscripciones ANTES de detener el player para que el
    //    BehaviorSubject de playbackState no reciba eventos mientras
    //    super.stop() intenta hacer .add() sobre él.
    await _detachPlayerListeners();

    // 2. Detener el player
    await _player.stop();
    _sessionManager.abandonAudioFocus();

    // 3. Ahora super.stop() puede llamar a playbackState.add() sin conflicto
    await super.stop();

    // 4. Reconectar listeners para que el estado siga siendo reactivo
    _attachPlayerListeners();
  }

  /// Avanzar al siguiente párrafo/chunk.
  @override
  Future<void> skipToNext() async {
    if (_currentChunkIndex < _chunkPaths.length - 1) {
      _currentChunkIndex++;
      // Detener sin llamar super.stop() (no queremos cerrar el servicio)
      await _detachPlayerListeners();
      await _player.stop();
      _attachPlayerListeners();
      await _playCurrentChunk();
    } else {
      // Fin del capítulo
      await stop();
    }
  }

  /// Retroceder al párrafo/chunk anterior.
  @override
  Future<void> skipToPrevious() async {
    // Si llevamos menos de 3 segundos en el chunk actual, ir al anterior
    final position = _player.position;
    if (position.inSeconds < 3 && _currentChunkIndex > 0) {
      _currentChunkIndex--;
    } else {
      // Si no, reiniciar el chunk actual desde el inicio
      await _player.seek(Duration.zero);
      return;
    }
    // Detener y reconectar igual que en skipToNext
    await _detachPlayerListeners();
    await _player.stop();
    _attachPlayerListeners();
    await _playCurrentChunk();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // ─── Controles Personalizados (botones extra en la notificación) ─────────────

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'jumpToChunk':
        final index = extras?['index'] as int?;
        if (index != null && index >= 0 && index < _chunkPaths.length) {
          _currentChunkIndex = index;
          await _detachPlayerListeners();
          await _player.stop();
          _attachPlayerListeners();
          await _playCurrentChunk();
        }
        break;
      case 'setChunkPaths':
        final paths = (extras?['paths'] as List?)?.cast<String>();
        if (paths != null) {
          _chunkPaths
            ..clear()
            ..addAll(paths);
        }
        break;
    }
  }

  // ─── Private Helpers ─────────────────────────────────────────────────────────

  Future<void> _playCurrentChunk() async {
    if (_chunkPaths.isEmpty || _currentChunkIndex >= _chunkPaths.length) return;

    final path = _chunkPaths[_currentChunkIndex];

    // Notificar al UI el chunk actual
    _currentChunkStreamController.add(_currentChunkIndex);

    // Actualizar MediaItem con el chunk actual
    final current = mediaItem.value;
    if (current != null) {
      mediaItem.add(current.copyWith(
        id: path,
        extras: {'chunkIndex': _currentChunkIndex},
      ));
    }

    // Asegurar Audio Focus antes de reproducir
    final focused = await _sessionManager.requestAudioFocus();
    if (!focused) return;

    await _player.setFilePath(path);
    await _player.play();
  }

  void _onChunkCompleted() {
    if (_currentChunkIndex < _chunkPaths.length - 1) {
      _currentChunkIndex++;
      _playCurrentChunk();
    } else {
      // Fin del capítulo: detener limpiamente
      stop();
    }
  }

  /// Convierte el estado de just_audio al estado de audio_service.
  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2], // Prev, Play/Pause, Next
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentChunkIndex,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    await _detachPlayerListeners();
    await _player.stop();
    _sessionManager.abandonAudioFocus();
    await super.stop();
    await _player.dispose();
    _currentChunkStreamController.close();
    _sessionManager.dispose();
  }
}
