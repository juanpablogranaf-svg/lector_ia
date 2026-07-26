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

  // ─── Constructor ─────────────────────────────────────────────────────────────

  LectorIaAudioHandler() {
    _initPlayer();
    _sessionManager.init();
  }

  void _initPlayer() {
    // Propagar eventos del player a AudioService
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Auto-avanzar al siguiente chunk cuando termina el actual
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onChunkCompleted();
      }
    });
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

    await _playCurrentChunk();
  }

  /// Carga un chunk individual y lo reproduce (para modo single-chunk).
  Future<void> loadAndPlayChunk(String audioFilePath) async {
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
    await _player.stop();
    _sessionManager.abandonAudioFocus();
    await super.stop();
  }

  /// Avanzar al siguiente párrafo/chunk.
  @override
  Future<void> skipToNext() async {
    if (_currentChunkIndex < _chunkPaths.length - 1) {
      _currentChunkIndex++;
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
    await stop();
    await _player.dispose();
    _currentChunkStreamController.close();
    _sessionManager.dispose();
  }
}
