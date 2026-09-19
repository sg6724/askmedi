import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF1B3A5C);
  static const teal = Color(0xFF2BAE8E);
  static const tealLight = Color(0xFFE3F5EF);
  static const sky = Color(0xFFE6F0FB);
  static const blush = Color(0xFFFCE4EC);
  static const lavender = Color(0xFFEDE7F6);
  static const peach = Color(0xFFFDE8DA);
  static const surface = Color(0xFFF7FAFC);
  static const danger = Color(0xFFD64545);
  static const textPrimary = Color(0xFF1B2B3A);
  static const textSecondary = Color(0xFF5B6B7B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    secondary: AppColors.teal,
    error: AppColors.danger,
    surface: AppColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
