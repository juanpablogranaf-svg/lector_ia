import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../constants/app_constants.dart';

/// Un fragmento de texto listo para ser enviado al TTS.
class TextChunk {
  final int index;
  final String text;
  final String hash;       // MD5 único para usar como clave de caché
  final int startOffset;  // Posición en el texto original
  final int endOffset;

  const TextChunk({
    required this.index,
    required this.text,
    required this.hash,
    required this.startOffset,
    required this.endOffset,
  });

  /// Duración estimada de reproducción (en segundos) a velocidad 1x.
  /// Aproximación: ~15 caracteres por segundo en español.
  double get estimatedDurationSeconds => text.length / 15.0;

  @override
  String toString() => 'TextChunk($index, chars: ${text.length}, hash: $hash)';
}

/// Fragmenta texto en chunks óptimos para enviar a la API TTS.
///
/// Estrategia:
/// 1. Divide por párrafos (doble salto de línea)
/// 2. Si un párrafo supera [maxChunk], lo divide por oraciones
/// 3. Si una oración supera [maxChunk], la divide por comas/punto y coma
/// 4. Nunca corta a la mitad de una palabra
class TextChunker {
  final int maxChunk;
  final int minChunk;

  const TextChunker({
    this.maxChunk = AppConstants.maxChunkCharacters,
    this.minChunk = AppConstants.minChunkCharacters,
  });

  // RegExp para detectar finales de oración (. ! ? seguidos de espacio/newline)
  static final _sentenceEnd = RegExp(r'(?<=[.!?…])\s+');

  // RegExp para dividir por coma, punto y coma, dos puntos
  static final _clauseBreak = RegExp(r'(?<=[,;:])\s+');

  /// Toma el texto completo y retorna la lista de chunks.
  List<TextChunk> chunk(String text) {
    final cleaned = _cleanText(text);
    final paragraphs = _splitParagraphs(cleaned);
    final chunks = <TextChunk>[];
    int globalOffset = 0;
    int chunkIndex = 0;

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) {
        globalOffset += paragraph.length + 2; // +2 por el doble \n
        continue;
      }

      final subChunks = _splitParagraph(paragraph, globalOffset, chunkIndex);
      chunks.addAll(subChunks);
      chunkIndex += subChunks.length;
      globalOffset += paragraph.length + 2;
    }

    // Fusionar chunks demasiado pequeños con el anterior
    return _mergeSmallChunks(chunks);
  }

  // ─── Private Methods ────────────────────────────────────────────────────────

  String _cleanText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n') // máximo doble newline
        .replaceAll(RegExp(r'[ \t]+'), ' ')     // espacios múltiples
        .trim();
  }

  List<String> _splitParagraphs(String text) {
    return text.split(RegExp(r'\n\n+'));
  }

  List<TextChunk> _splitParagraph(String paragraph, int baseOffset, int startIndex) {
    if (paragraph.length <= maxChunk) {
      return [_createChunk(startIndex, paragraph.trim(), baseOffset, baseOffset + paragraph.length)];
    }

    // Intentar dividir por oraciones primero
    final sentences = paragraph.trim().split(_sentenceEnd);
    if (sentences.length > 1) {
      return _buildChunksFromParts(sentences, baseOffset, startIndex);
    }

    // Si no hay oraciones claras, dividir por cláusulas
    final clauses = paragraph.trim().split(_clauseBreak);
    if (clauses.length > 1) {
      return _buildChunksFromParts(clauses, baseOffset, startIndex);
    }

    // Último recurso: división por longitud respetando palabras
    return _splitByLength(paragraph.trim(), baseOffset, startIndex);
  }

  List<TextChunk> _buildChunksFromParts(
    List<String> parts, int baseOffset, int startIndex,
  ) {
    final chunks = <TextChunk>[];
    var buffer = StringBuffer();
    int bufferStart = baseOffset;
    int currentOffset = baseOffset;
    int index = startIndex;

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) {
        currentOffset += parts[i].length + 1;
        continue;
      }

      final potentialLength = buffer.isEmpty
          ? part.length
          : buffer.length + 1 + part.length;

      if (potentialLength > maxChunk && buffer.isNotEmpty) {
        // Emitir chunk actual
        chunks.add(_createChunk(index++, buffer.toString().trim(), bufferStart, currentOffset));
        buffer.clear();
        bufferStart = currentOffset;
      }

      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(part);
      currentOffset += parts[i].length + 1;
    }

    if (buffer.isNotEmpty) {
      chunks.add(_createChunk(index, buffer.toString().trim(), bufferStart, currentOffset));
    }

    return chunks;
  }

  List<TextChunk> _splitByLength(String text, int baseOffset, int startIndex) {
    final chunks = <TextChunk>[];
    int start = 0;
    int index = startIndex;

    while (start < text.length) {
      int end = (start + maxChunk).clamp(0, text.length);

      // Retroceder hasta el último espacio para no cortar palabras
      if (end < text.length) {
        final spaceIndex = text.lastIndexOf(' ', end);
        if (spaceIndex > start) end = spaceIndex;
      }

      final slice = text.substring(start, end).trim();
      if (slice.isNotEmpty) {
        chunks.add(_createChunk(
          index++,
          slice,
          baseOffset + start,
          baseOffset + end,
        ));
      }
      start = end + 1;
    }

    return chunks;
  }

  List<TextChunk> _mergeSmallChunks(List<TextChunk> chunks) {
    if (chunks.isEmpty) return chunks;
    final result = <TextChunk>[];
    var current = chunks.first;

    for (int i = 1; i < chunks.length; i++) {
      final next = chunks[i];
      if (current.text.length < minChunk && (current.text.length + next.text.length + 1) <= maxChunk) {
        // Fusionar con el siguiente
        final mergedText = '${current.text} ${next.text}';
        current = _createChunk(
          current.index,
          mergedText,
          current.startOffset,
          next.endOffset,
        );
      } else {
        result.add(current);
        current = next;
      }
    }
    result.add(current);

    // Re-indexar
    return List.generate(result.length, (i) {
      final c = result[i];
      if (c.index != i) {
        return _createChunk(i, c.text, c.startOffset, c.endOffset);
      }
      return c;
    });
  }

  TextChunk _createChunk(int index, String text, int start, int end) {
    final hash = _computeHash(text);
    return TextChunk(
      index: index,
      text: text,
      hash: hash,
      startOffset: start,
      endOffset: end,
    );
  }

  static String _computeHash(String text) {
    final bytes = utf8.encode(text);
    return md5.convert(bytes).toString();
  }
}
