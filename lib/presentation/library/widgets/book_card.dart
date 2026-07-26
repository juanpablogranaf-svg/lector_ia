import 'package:flutter/material.dart';
import '../../../../data/models/book_model.dart';
import '../../../../data/models/reading_progress_model.dart';

class BookCard extends StatelessWidget {
  final BookModel book;
  final ReadingProgressModel? progress;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookCard({
    super.key,
    required this.book,
    this.progress,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progressPercent = progress?.progressPercent ?? 0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: book.coverPath != null
                    ? Image.asset(book.coverPath!, fit: BoxFit.cover, width: double.infinity)
                    : _buildDefaultCover(context, cs),
              ),
            ),

            // Progress bar
            if (progressPercent > 0)
              LinearProgressIndicator(
                value: progressPercent / 100,
                minHeight: 3,
                backgroundColor: cs.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),

            // Book info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (book.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _FormatBadge(format: book.fileType.toUpperCase()),
                      const Spacer(),
                      if (progressPercent > 0)
                        Text(
                          '$progressPercent%',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover(BuildContext context, ColorScheme cs) {
    // Generar un color único basado en el título
    final hue = (book.title.hashCode % 360).abs().toDouble();
    final coverColor = HSLColor.fromAHSL(1, hue, 0.6, 0.3).toColor();
    final iconColor = HSLColor.fromAHSL(1, hue, 0.6, 0.8).toColor();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [coverColor, coverColor.withOpacity(0.7)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories, size: 48, color: iconColor.withOpacity(0.8)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              book.title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  final String format;
  const _FormatBadge({required this.format});

  static const _colors = {
    'EPUB': Color(0xFF4CAF50),
    'PDF': Color(0xFFEF5350),
    'TXT': Color(0xFF42A5F5),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[format] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        format,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
