import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF070B14);
  static const surface = Color(0xFF101827);
  static const surfaceStrong = Color(0xFF151F32);
  static const border = Color(0xFF243754);
  static const cyan = Color(0xFF21D7FF);
  static const violet = Color(0xFF7C5CFF);
  static const mint = Color(0xFF39E6A4);
  static const danger = Color(0xFFFF5F77);
  static const textMuted = Color(0xFF91A3BD);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.cyan,
    brightness: Brightness.dark,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      titleLarge: TextStyle(fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(height: 1.35),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xF20C1320),
      indicatorColor: Color(0x3321D7FF),
      height: 72,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      selectedColor: AppColors.cyan.withValues(alpha: 0.16),
      backgroundColor: AppColors.surface.withValues(alpha: 0.75),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
