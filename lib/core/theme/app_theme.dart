import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF1B9E6B);
  static const Color primaryDark = Color(0xFF0E6B45);
  static const Color secondary = Color(0xFFFFB020);
  static const Color accentMint = Color(0xFFE6F7EE);
  static const Color background = Color(0xFFF7FAF8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF12261C);
  static const Color muted = Color(0xFF6B7D72);
  static const Color error = Color(0xFFE5484D);
  static const Color darkBackground = Color(0xFF0C1712);
  static const Color darkSurface = Color(0xFF152219);
}

ThemeData buildLightTheme() => _build(Brightness.light);
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? AppColors.darkBackground : AppColors.background;
  final surf = isDark ? AppColors.darkSurface : AppColors.surface;
  final ink = isDark ? const Color(0xFFE8F2EC) : AppColors.ink;
  final muted = isDark ? const Color(0xFF9DB4A6) : AppColors.muted;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    error: AppColors.error,
    surface: surf,
  );

  final heading = GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800);
  final bodyFont = GoogleFonts.inter();

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: bodyFont.fontFamily,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          displaySmall: heading.copyWith(color: ink, fontSize: 28),
          headlineMedium: heading.copyWith(color: ink, fontSize: 24),
          headlineSmall: heading.copyWith(color: ink, fontSize: 20),
          titleLarge: heading.copyWith(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: bodyFont.copyWith(color: ink, fontSize: 14),
          bodySmall: bodyFont.copyWith(color: muted, fontSize: 12),
          labelLarge: bodyFont.copyWith(fontWeight: FontWeight.w600),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: heading.copyWith(color: ink, fontSize: 19),
    ),
    cardTheme: CardThemeData(
      color: surf,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF23402F) : const Color(0xFFE3EDE6),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.primary),
        foregroundColor: AppColors.primary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surf,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF23402F) : const Color(0xFFDCE8DF),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF23402F) : const Color(0xFFDCE8DF),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(
        color: isDark ? const Color(0xFF23402F) : const Color(0xFFDCE8DF),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surf,
      indicatorColor: AppColors.accentMint,
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
