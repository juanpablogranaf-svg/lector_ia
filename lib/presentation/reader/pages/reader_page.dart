import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:epub_view/epub_view.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
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
  pdfx.PdfController? _pdfController;
  final _scrollController = ScrollController();
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    context.read<ReaderBloc>().add(ReaderBookOpened(widget.bookId));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _epubController?.dispose();
    _pdfController?.dispose();
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
      listenWhen: (p, c) => p.status != c.status || p.book != c.book,
      listener: (context, state) {
        if (state.status == ReaderStatus.loaded && state.book != null) {
          _initViewer(state);
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
    final book = state.book!;

    if (book.fileType == 'epub') {
      _epubController = EpubController(
        document: EpubDocument.openFile(File(book.filePath)),
        epubCfi: null, // Restaurar CFI guardado si existe
      );
    } else if (book.fileType == 'pdf') {
      _pdfController = pdfx.PdfController(
        document: pdfx.PdfDocument.openFile(book.filePath),
        initialPage: state.progress?.pageNumber ?? 0,
      );
    }
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
        return pdfx.PdfView(
          controller: _pdfController!,
          onPageChanged: (page) => context.read<ReaderBloc>().add(
            ReaderScrollPositionChanged(
              page / (_pdfController!.pagesCount ?? 1),
              page,
            ),
          ),
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

