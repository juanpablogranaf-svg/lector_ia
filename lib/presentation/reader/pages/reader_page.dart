import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:epub_view/epub_view.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import '../bloc/reader_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/tts_player_bar.dart';
import '../widgets/reader_settings_panel.dart';

class ReaderPage extends StatefulWidget {
  final String bookId;
  const ReaderPage({super.key, required this.bookId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  EpubController? _epubController;
  pdfrx.PdfViewerController? _pdfController;
  final _scrollController = ScrollController();
  bool _showControls = true;
  pdfrx.PdfDocument? _pdfDocument;
  epubx.EpubBook? _epubBook; // Cache del libro EPUB para extracción directa
  bool _epubTextExtracted = false; // Bandera para evitar re-extracciones duplicadas
  int? _lastEpubChapterNumber; // Último capítulo notificado por el listener

  @override
  void initState() {
    super.initState();
    context.read<ReaderBloc>().add(ReaderBookOpened(widget.bookId));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _epubController?.currentValueListenable.removeListener(_onEpubChapterChanged);
    _epubController?.dispose();

    context.read<ReaderBloc>().add(const ReaderClosed());
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final progress = position.pixels / position.maxScrollExtent;
    context.read<ReaderBloc>().add(
      ReaderScrollPositionChanged(progress.clamp(0.0, 1.0), position.pixels.toInt()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReaderBloc, ReaderState>(
      listenWhen: (p, c) => p.status != c.status || p.book != c.book || p.ttsStatus != c.ttsStatus,
      listener: (context, state) {
        if (state.status == ReaderStatus.loaded && state.book != null) {
          _initViewer(state);
        }
        if (state.ttsStatus == TtsStatus.error && (state.ttsErrorMessage?.contains('No hay texto disponible') ?? false)) {
          // Si no hay texto al presionar Play, intentar buscar el siguiente bloque legible automáticamente
          if (state.book?.fileType == 'epub') {
            // Para EPUB, hacer scroll hacia adelante para forzar carga del siguiente capítulo
            debugPrint('[ReaderPage] Empty text on Play, scrolling forward to find next EPUB text...');
            if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          } else if (state.book?.fileType == 'pdf' && _pdfController != null && _pdfDocument != null) {
            final currentPage = _pdfController!.pageNumber ?? 1;
            final totalPages = _pdfDocument!.pages.length;
            if (currentPage < totalPages) {
              debugPrint('[ReaderPage] Empty text on Play, seeking next PDF page: ${currentPage + 1}...');
              _pdfController!.goToPage(pageNumber: currentPage + 1);
            }
          }
        }
      },
      builder: (context, state) {
        final theme = ReaderThemeData.of(state.readerTheme);

        return Scaffold(
          backgroundColor: theme.background,
          body: GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: Stack(
              children: [
                // Content Viewer
                if (state.status == ReaderStatus.loading)
                  _buildLoadingState(theme)
                else if (state.status == ReaderStatus.error)
                  _buildErrorState(state.errorMessage ?? '')
                else if (state.book != null)
                  _buildViewer(state, theme)
                else
                  const SizedBox.shrink(),

                // Top App Bar (animado)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: _showControls ? 0 : -100,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(context, state, theme),
                ),

                // TTS Player Bar (bottom)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  bottom: _showControls ? 0 : -120,
                  left: 0,
                  right: 0,
                  child: TtsPlayerBar(
                    readerTheme: state.readerTheme,
                    currentChunk: state.currentChunk,
                    totalChunks: state.chunks.length,
                    ttsStatus: state.ttsStatus,
                    ttsSpeed: state.ttsSpeed,
                    ttsErrorMessage: state.ttsErrorMessage,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _initViewer(ReaderState state) {
    try {
      final book = state.book!;

      if (book.fileType == 'epub') {
        _epubController = EpubController(
          document: EpubDocument.openFile(File(book.filePath)),
          epubCfi: null,
        );
        // Escuchar cambios de capítulo para extraer texto al Bloc
        _epubController!.currentValueListenable.addListener(_onEpubChapterChanged);
        // Precargar el EpubBook directamente para extracción de texto robusta
        _loadEpubBookForTextExtraction(book.filePath);
      } else if (book.fileType == 'pdf') {
        _pdfController = pdfrx.PdfViewerController();
      }
    } catch (e) {
      debugPrint('[ReaderPage] Error in _initViewer: $e');
    }
  }

  /// Carga el EpubBook directamente desde el archivo para poder extraer
  /// el HTML de los capítulos sin depender del render del widget.
  Future<void> _loadEpubBookForTextExtraction(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      _epubBook = await epubx.EpubReader.readBook(bytes);
      debugPrint('[ReaderPage] EpubBook loaded for text extraction: ${_epubBook?.Title}');
      
      // Si el listener ya disparó pero no pudo extraer texto (libro aún no cargado),
      // intentamos ahora con el último capítulo notificado
      if (!_epubTextExtracted) {
        final currentValue = _epubController?.currentValueListenable.value;
        if (currentValue != null) {
          debugPrint('[ReaderPage] EpubBook ready, retrying extraction for pending chapter...');
          _extractAndSendEpubText(currentValue);
        } else if (_epubBook != null) {
          // Extraer directamente el primer capítulo con texto
          _extractFromEpubBookChapter(0);
        }
      }
    } catch (e) {
      debugPrint('[ReaderPage] Error loading EpubBook for text extraction: $e');
    }
  }

  /// Llamado cuando el EpubController cambia de capítulo/página.
  void _onEpubChapterChanged() {
    final value = _epubController?.currentValueListenable.value;
    if (value == null) return;
    // Resetear flag cuando cambia de capítulo para permitir re-extracción
    final newChapter = value.chapterNumber as int?;
    if (newChapter != _lastEpubChapterNumber) {
      _epubTextExtracted = false;
    }
    _extractAndSendEpubText(value);
  }

  /// Extrae el texto plano del capítulo EPUB y lo envía al Bloc.
  /// Estrategia dual:
  /// 1. Intenta usar value.paragraphs (render del widget)
  /// 2. Si está vacío, usa el EpubBook cargado directamente para leer el HTML del capítulo
  void _extractAndSendEpubText(dynamic value) {
    // Obtener número de capítulo actual
    final chapterNumber = value.chapterNumber as int?;
    if (chapterNumber == null) return;

    try {
      // Estrategia 1: extraer desde los párrafos del widget renderizado
      final htmlContent = (value.paragraphs as List?)  
          ?.map((p) {
            try { return (p.element.innerHtml as String?) ?? ''; }
            catch (_) { return ''; }
          })
          .join('\n\n') ?? '';

      final plainText = _stripHtml(htmlContent).trim();

      if (plainText.isNotEmpty) {
        debugPrint('[ReaderPage] EPUB: extracted ${plainText.length} chars from paragraphs (chapter $chapterNumber)');
        _epubTextExtracted = true;
        _lastEpubChapterNumber = chapterNumber;
        if (mounted) context.read<ReaderBloc>().add(ReaderTextExtracted(plainText));
        return;
      }

      // Estrategia 2: extraer directamente del EpubBook si el widget no tiene párrafos
      final book = _epubBook;
      if (book != null) {
        _lastEpubChapterNumber = chapterNumber;
        _extractFromEpubBookChapter(chapterNumber - 1);
        return;
      }

      // EpubBook aún no cargado — guardar el número de capítulo para procesarlo cuando cargue
      _lastEpubChapterNumber = chapterNumber;
      debugPrint('[ReaderPage] EPUB chapter $chapterNumber: EpubBook not loaded yet, will retry when ready.');
    } catch (e) {
      debugPrint('[ReaderPage] EPUB text extraction error: $e');
      // Fallback al libro cargado si hay error
      final chNum = value.chapterNumber as int?;
      if (chNum != null && _epubBook != null) {
        _extractFromEpubBookChapter(chNum - 1);
      }
    }
  }

  /// Extrae texto directamente del HTML del capítulo desde el EpubBook.
  /// Si el capítulo objetivo está vacío (portada, imagen), avanza al siguiente con texto.
  void _extractFromEpubBookChapter(int chapterIndex) {
    try {
      final book = _epubBook;
      if (book == null) return;

      final chapters = book.Chapters;
      if (chapters == null || chapters.isEmpty) return;

      String extractChapterText(epubx.EpubChapter chapter) {
        final buffer = StringBuffer();
        final htmlContent = chapter.HtmlContent ?? '';
        if (htmlContent.isNotEmpty) {
          buffer.write(_stripHtml(htmlContent));
          buffer.write('\n\n');
        }
        for (final sub in chapter.SubChapters ?? <epubx.EpubChapter>[]) {
          buffer.write(extractChapterText(sub));
        }
        return buffer.toString();
      }

      // Buscar desde el índice objetivo hasta el final hasta encontrar texto
      final startIndex = chapterIndex.clamp(0, chapters.length - 1);
      for (int i = startIndex; i < chapters.length; i++) {
        final plainText = extractChapterText(chapters[i]).trim();
        if (plainText.isNotEmpty && mounted) {
          debugPrint('[ReaderPage] EPUB: extracted ${plainText.length} chars from EpubBook chapter $i');
          _epubTextExtracted = true;
          context.read<ReaderBloc>().add(ReaderTextExtracted(plainText));
          return;
        }
      }
      debugPrint('[ReaderPage] EPUB: no readable text found in any chapter from index $startIndex');
    } catch (e) {
      debugPrint('[ReaderPage] EpubBook chapter extraction error: $e');
    }
  }

  /// Extrae texto de una página PDF y lo envía al Bloc.
  Future<void> _extractAndSendPdfText(pdfrx.PdfDocument doc, int pageNumber) async {
    try {
      final page = doc.pages[pageNumber - 1];
      final text = await page.loadText();
      final extracted = text.fullText.trim();
      if (extracted.isNotEmpty) {
        if (mounted) {
          context.read<ReaderBloc>().add(ReaderTextExtracted(extracted));
        }
      } else {
        // Página vacía o imagen, avanzar automáticamente a la siguiente
        final totalPages = doc.pages.length;
        if (pageNumber < totalPages) {
          debugPrint('[ReaderPage] PDF page $pageNumber is empty. Auto-seeking page ${pageNumber + 1}...');
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _pdfController?.goToPage(pageNumber: pageNumber + 1);
          });
        }
      }
    } catch (e) {
      debugPrint('[ReaderPage] PDF text extraction error: $e');
    }
  }

  /// Quita etiquetas HTML básicas para obtener texto plano legible por TTS.
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>',  caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<p[^>]*>',   caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>',        caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'),    '')
        .replaceAll(RegExp(r'&nbsp;'),     ' ')
        .replaceAll(RegExp(r'&amp;'),      '&')
        .replaceAll(RegExp(r'&lt;'),       '<')
        .replaceAll(RegExp(r'&gt;'),       '>')
        .replaceAll(RegExp(r'&quot;'),     '"')
        .replaceAll(RegExp(r'\n{3,}'),     '\n\n')
        .trim();
  }

  Widget _buildViewer(ReaderState state, ReaderThemeData theme) {
    final book = state.book!;
    final margin = EdgeInsets.all(state.margin);

    switch (book.fileType) {
      case 'epub':
        if (_epubController == null) return const SizedBox.shrink();
        return EpubView(
          controller: _epubController!,
          builders: EpubViewBuilders<DefaultBuilderOptions>(
            options: DefaultBuilderOptions(
              textStyle: TextStyle(
                fontSize: state.fontSize,
                color: theme.text,
                height: state.lineHeight,
              ),
            ),
            chapterDividerBuilder: (_) => const Divider(height: 1),
            loaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
          ),
        );

      case 'pdf':
        if (_pdfController == null) return const SizedBox.shrink();
        return pdfrx.PdfViewer.file(
          book.filePath,
          controller: _pdfController,
          params: pdfrx.PdfViewerParams(
            onDocumentChanged: (doc) {
              try {
                if (doc != null) {
                  _pdfDocument = doc;
                  // Extraer texto de la primera página al cargar el documento
                  final initialPage = state.progress?.pageNumber != null
                      ? state.progress!.pageNumber + 1
                      : 1;
                  _extractAndSendPdfText(doc, initialPage);
                }
              } catch (e) {
                debugPrint('[ReaderPage] Error in onDocumentChanged: $e');
              }
            },
            onPageChanged: (int? pageNumber) {
              try {
                if (pageNumber != null) {
                  // Acceso seguro: preferir _pdfDocument.pages.length, luego _pdfController.pageCount
                  int totalPages = 1;
                  if (_pdfDocument != null) {
                    totalPages = _pdfDocument!.pages.length;
                  } else {
                    totalPages = _pdfController?.pageCount ?? 1;
                  }
                  
                  context.read<ReaderBloc>().add(
                    ReaderScrollPositionChanged(
                      pageNumber / totalPages,
                      pageNumber - 1,
                    ),
                  );
                  
                  // Extraer texto de la nueva página para TTS de manera segura
                  if (_pdfDocument != null) {
                    _extractAndSendPdfText(_pdfDocument!, pageNumber);
                  }
                }
              } catch (e) {
                debugPrint('[ReaderPage] Error in onPageChanged: $e');
              }
            },
          ),
          initialPageNumber: state.progress?.pageNumber != null ? state.progress!.pageNumber + 1 : 1,
        );

      case 'txt':
      default:
        return _buildTxtViewer(state, theme, margin);
    }
  }

  Widget _buildTxtViewer(ReaderState state, ReaderThemeData theme, EdgeInsets margin) {
    return ListView.builder(
      controller: _scrollController,
      padding: margin.copyWith(top: 100, bottom: 140),
      itemCount: state.chunks.length,
      itemBuilder: (context, index) {
        final chunk = state.chunks[index];
        final isCurrent = index == state.currentChunkIndex && state.isTtsPlaying;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 12),
          padding: isCurrent
              ? const EdgeInsets.all(8)
              : EdgeInsets.zero,
          decoration: isCurrent
              ? BoxDecoration(
                  color: theme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.accent.withOpacity(0.3)),
                )
              : null,
          child: Text(
            chunk.text,
            style: TextStyle(
              fontSize: state.fontSize,
              color: isCurrent ? theme.text : theme.text.withOpacity(0.85),
              height: state.lineHeight,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, ReaderState state, ReaderThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.background, theme.background.withOpacity(0)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios, color: theme.text, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  state.book?.title ?? '',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.text_fields, color: theme.text, size: 20),
                onPressed: () => _showSettings(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<ReaderBloc>(),
        child: const ReaderSettingsPanel(),
      ),
    );
  }

  Widget _buildLoadingState(ReaderThemeData theme) {
    return Center(
      child: CircularProgressIndicator(color: theme.accent),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

