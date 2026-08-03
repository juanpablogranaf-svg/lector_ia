import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/reader_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/text_chunker.dart';

class TtsPlayerBar extends StatefulWidget {
  final ReaderTheme readerTheme;
  final TextChunk? currentChunk;
  final int totalChunks;
  final TtsStatus ttsStatus;
  final double ttsSpeed;
  final String ttsErrorMessage;

  const TtsPlayerBar({
    super.key,
    required this.readerTheme,
    required this.currentChunk,
    required this.totalChunks,
    required this.ttsStatus,
    required this.ttsSpeed,
    required this.ttsErrorMessage,
  });

  @override
  State<TtsPlayerBar> createState() => _TtsPlayerBarState();
}

class _TtsPlayerBarState extends State<TtsPlayerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderThemeData.of(widget.readerTheme);
    final isPlaying = widget.ttsStatus == TtsStatus.playing;
    final isLoading = widget.ttsStatus == TtsStatus.loading;
    final hasError = widget.ttsStatus == TtsStatus.error;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.background.withOpacity(0),
            theme.background,
            theme.background,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.accent.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
            border: Border.all(
              color: isPlaying
                  ? theme.accent.withOpacity(0.4)
                  : theme.text.withOpacity(0.1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error message
              if (hasError && widget.ttsErrorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.ttsErrorMessage,
                          style: const TextStyle(color: Colors.orange, fontSize: 11),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),

              // Current chunk preview
              if (widget.currentChunk != null && widget.ttsStatus != TtsStatus.idle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: isPlaying ? _pulseAnimation.value : 0.7,
                        child: Text(
                          widget.currentChunk!.text.length > 80
                              ? '${widget.currentChunk!.text.substring(0, 80)}...'
                              : widget.currentChunk!.text,
                          style: TextStyle(
                            color: theme.text.withOpacity(0.7),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),

              // Controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Speed button
                  _SpeedButton(
                    speed: widget.ttsSpeed,
                    color: theme.accent,
                    onTap: () => _cycleSpeed(context),
                  ),

                  // Prev chunk
                  _ControlButton(
                    icon: Icons.skip_previous_rounded,
                    color: theme.text.withOpacity(0.7),
                    size: 28,
                    onTap: () => context.read<ReaderBloc>().add(const ReaderTtsPrevChunk()),
                  ),

                  // Play / Pause (button principal)
                  GestureDetector(
                    onTap: () => context.read<ReaderBloc>().add(const ReaderTtsPlayToggled()),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPlaying
                              ? [theme.accent, theme.accent.withOpacity(0.7)]
                              : [theme.accent.withOpacity(0.8), theme.accent.withOpacity(0.5)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.accent.withOpacity(isPlaying ? 0.4 : 0.15),
                            blurRadius: isPlaying ? 16 : 8,
                            spreadRadius: isPlaying ? 2 : 0,
                          ),
                        ],
                      ),
                      child: isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),

                  // Next chunk
                  _ControlButton(
                    icon: Icons.skip_next_rounded,
                    color: theme.text.withOpacity(0.7),
                    size: 28,
                    onTap: () => context.read<ReaderBloc>().add(const ReaderTtsNextChunk()),
                  ),

                  // Chunk counter
                  if (widget.currentChunk != null && widget.totalChunks > 0)
                    Text(
                      '${widget.currentChunk!.index + 1}/${widget.totalChunks}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.text.withOpacity(0.5),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  else
                    Text(
                      'TTS',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleSpeed(BuildContext context) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final currentIndex = speeds.indexWhere((s) => (s - widget.ttsSpeed).abs() < 0.01);
    final nextSpeed = speeds[(currentIndex + 1) % speeds.length];
    context.read<ReaderBloc>().add(ReaderTtsSpeedChanged(nextSpeed));
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final Color color;
  final VoidCallback onTap;

  const _SpeedButton({
    required this.speed,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Center(
          child: Text(
            '${speed}x',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}


