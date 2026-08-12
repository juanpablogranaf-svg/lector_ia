import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import '../../../data/models/book_model.dart';
import '../bloc/library_bloc.dart';
import '../widgets/book_card.dart';
import '../widgets/scan_progress_indicator.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildAppBar(context, cs, innerBoxIsScrolled),
        ],
        body: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            if (state.status == LibraryStatus.scanning && state.books.isEmpty) {
              return _buildLoadingGrid(context);
            }
            if (state.status == LibraryStatus.error) {
              return _buildError(context, state.errorMessage ?? '');
            }
            if (state.filteredBooks.isEmpty && state.status == LibraryStatus.loaded) {
              return _buildEmptyState(context);
            }
            return _buildBookGrid(context, state);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndImportFile(context),
        tooltip: 'Añadir archivo',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _pickAndImportFile(BuildContext context) async {
    try {
      // Necesitamos importar file_picker
      final result = await file_picker.FilePicker.platform.pickFiles(
        type: file_picker.FileType.custom,
        allowedExtensions: ['pdf', 'epub', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final stat = await file.stat();
        final ext = filePath.split('.').last.toLowerCase();
        
        final book = BookModel.fromFile(file, stat, ext);
        if (context.mounted) {
          context.read<LibraryBloc>().add(LibraryBookImported(book));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Libro "${book.title}" añadido con éxito.'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  SliverAppBar _buildAppBar(BuildContext context, ColorScheme cs, bool innerBoxIsScrolled) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: _showSearch
          ? _buildSearchField(context)
          : FadeTransition(
              opacity: _fadeController,
              child: Row(
                children: [
                  Icon(Icons.auto_stories, color: cs.primary, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'LectorIA',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _showSearch ? Icons.close : Icons.search,
              key: ValueKey(_showSearch),
              color: cs.primary,
            ),
          ),
          onPressed: () {
            setState(() => _showSearch = !_showSearch);
            if (!_showSearch) {
              _searchController.clear();
              context.read<LibraryBloc>().add(const LibrarySearchChanged(''));
            }
          },
        ),
        PopupMenuButton<LibrarySortBy>(
          icon: Icon(Icons.sort, color: cs.primary),
          onSelected: (sort) =>
              context.read<LibraryBloc>().add(LibrarySortChanged(sort)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: LibrarySortBy.recentlyAdded, child: Text('Añadido recientemente')),
            PopupMenuItem(value: LibrarySortBy.lastOpened, child: Text('Última apertura')),
            PopupMenuItem(value: LibrarySortBy.title, child: Text('Título')),
            PopupMenuItem(value: LibrarySortBy.author, child: Text('Autor')),
          ],
        ),
        IconButton(
          icon: Icon(Icons.light_mode_outlined, color: cs.primary),
          onPressed: () => context.read<LibraryBloc>().add(const LibraryThemeToggled()),
        ),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: cs.primary),
          onPressed: () => context.push('/settings'),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: BlocBuilder<LibraryBloc, LibraryState>(
          buildWhen: (p, c) => p.status != c.status || p.scanProgress != c.scanProgress,
          builder: (context, state) {
            if (state.status != LibraryStatus.scanning) return const SizedBox.shrink();
            return ScanProgressIndicator(found: state.scanProgress);
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        hintText: 'Buscar por título o autor...',
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (q) => context.read<LibraryBloc>().add(LibrarySearchChanged(q)),
    );
  }

  Widget _buildBookGrid(BuildContext context, LibraryState state) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: state.filteredBooks.length,
      itemBuilder: (context, index) {
        final book = state.filteredBooks[index];
        final progress = state.progressMap[book.id];
        return BookCard(
          book: book,
          progress: progress,
          onTap: () => context.push('/reader/${book.id}'),
          onLongPress: () => _showBookOptions(context, book.id),
        );
      },
    );
  }

  Widget _buildLoadingGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[700]!,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
          ),
          const SizedBox(height: 24),
          Text(
            'Tu biblioteca está vacía',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coloca archivos EPUB, PDF o TXT\nen tu almacenamiento y se detectarán\nautomáticamente.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Escanear de nuevo'),
            onPressed: () =>
                context.read<LibraryBloc>().add(const LibraryScanStarted()),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.read<LibraryBloc>().add(const LibraryScanStarted()),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  void _showBookOptions(BuildContext context, String bookId) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Eliminar de la biblioteca', style: TextStyle(color: Colors.red)),
              onTap: () {
                context.read<LibraryBloc>().add(LibraryBookDeleted(bookId));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
