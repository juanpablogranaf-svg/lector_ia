import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ─── Color Palette ──────────────────────────────────────────────────────────
  static const _primaryDark = Color(0xFF6C63FF);      // Indigo vibrante
  static const _accentDark = Color(0xFF03DAC6);        // Teal accent
  static const _backgroundDark = Color(0xFF0D0D1A);   // Casi negro azulado
  static const _surfaceDark = Color(0xFF1A1A2E);       // Superficie oscura
  static const _cardDark = Color(0xFF16213E);          // Cards oscuras

  static const _primaryLight = Color(0xFF5048E5);
  static const _backgroundLight = Color(0xFFF4F4FC);
  static const _surfaceLight = Color(0xFFFFFFFF);

  // Sepia
  static const sepiaBackground = Color(0xFFF5ECD7);
  static const sepiaText = Color(0xFF3D2B1F);
  static const sepiaSurface = Color(0xFFEDD9B0);

  // ─── Light Theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryLight,
          brightness: Brightness.light,
          surface: _surfaceLight,
        ),
        scaffoldBackgroundColor: _backgroundLight,
        textTheme: GoogleFonts.outfitTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: _surfaceLight,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _primaryLight),
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: _surfaceLight,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryLight,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      );

  // ─── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryDark,
          brightness: Brightness.dark,
          surface: _surfaceDark,
          secondary: _accentDark,
        ),
        scaffoldBackgroundColor: _backgroundDark,
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: _surfaceDark,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: _primaryDark),
          titleTextStyle: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: _cardDark,
          shadowColor: _primaryDark.withOpacity(0.2),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryDark,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryDark.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primaryDark.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryDark, width: 2),
          ),
        ),
        dividerColor: Colors.white12,
      );
}

/// Temas específicos del visor de lectura
enum ReaderTheme { light, dark, sepia }

class ReaderThemeData {
  final Color background;
  final Color text;
  final Color surface;
  final Color accent;

  const ReaderThemeData({
    required this.background,
    required this.text,
    required this.surface,
    required this.accent,
  });

  static const light = ReaderThemeData(
    background: Color(0xFFFAFAFA),
    text: Color(0xFF1A1A2E),
    surface: Color(0xFFFFFFFF),
    accent: Color(0xFF5048E5),
  );

  static const dark = ReaderThemeData(
    background: Color(0xFF0D0D1A),
    text: Color(0xFFE8E8F0),
    surface: Color(0xFF1A1A2E),
    accent: Color(0xFF6C63FF),
  );

  static const sepia = ReaderThemeData(
    background: AppTheme.sepiaBackground,
    text: AppTheme.sepiaText,
    surface: AppTheme.sepiaSurface,
    accent: Color(0xFF8B5E3C),
  );

  static ReaderThemeData of(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return light;
      case ReaderTheme.dark:
        return dark;
      case ReaderTheme.sepia:
        return sepia;
    }
  }
}
