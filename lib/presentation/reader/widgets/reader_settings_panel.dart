import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/reader_bloc.dart';
import '../../../core/theme/app_theme.dart';

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReaderBloc, ReaderState>(
      builder: (context, state) {
        final theme = ReaderThemeData.of(state.readerTheme);

        return Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.text.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Ajustes de Lectura',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),

              // ─── Tema ────────────────────────────────────────────────────
              Text('Tema', style: _labelStyle(theme)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ThemeOption(
                    label: 'Claro',
                    background: ReaderThemeData.light.background,
                    textColor: ReaderThemeData.light.text,
                    selected: state.readerTheme == ReaderTheme.light,
                    onTap: () => context.read<ReaderBloc>().add(
                      const ReaderThemeChanged(ReaderTheme.light),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ThemeOption(
                    label: 'Oscuro',
                    background: ReaderThemeData.dark.background,
                    textColor: ReaderThemeData.dark.text,
                    selected: state.readerTheme == ReaderTheme.dark,
                    onTap: () => context.read<ReaderBloc>().add(
                      const ReaderThemeChanged(ReaderTheme.dark),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ThemeOption(
                    label: 'Sepia',
                    background: AppTheme.sepiaBackground,
                    textColor: AppTheme.sepiaText,
                    selected: state.readerTheme == ReaderTheme.sepia,
                    onTap: () => context.read<ReaderBloc>().add(
                      const ReaderThemeChanged(ReaderTheme.sepia),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ─── Tamaño de Fuente ────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tamaño de fuente', style: _labelStyle(theme)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${state.fontSize.round()}px',
                      style: TextStyle(color: theme.accent, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: theme.accent,
                  thumbColor: theme.accent,
                  overlayColor: theme.accent.withOpacity(0.15),
                  inactiveTrackColor: theme.text.withOpacity(0.15),
                ),
                child: Slider(
                  min: 12,
                  max: 32,
                  divisions: 10,
                  value: state.fontSize,
                  onChanged: (v) => context.read<ReaderBloc>().add(ReaderFontSizeChanged(v)),
                ),
              ),
              const SizedBox(height: 16),

              // ─── Preview ─────────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.text.withOpacity(0.1)),
                ),
                child: Text(
                  '«La vida es lo que ocurre mientras estás ocupado haciendo otros planes.» — John Lennon',
                  style: TextStyle(
                    fontSize: state.fontSize,
                    color: theme.text,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  TextStyle _labelStyle(ReaderThemeData theme) {
    return TextStyle(
      color: theme.text.withOpacity(0.7),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.background,
    required this.textColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF6C63FF) : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: selected
                ? [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 8)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
