import 'package:flutter/material.dart';

class PosexTheme {
  PosexTheme._();

  static const Color brandOrange = Color(0xFFF97316);
  static const Color brandOrangeLight = Color(0xFFFB923C);
  static const Color brandBlue = Color(0xFF3B82F6);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brandOrange,
      brightness: Brightness.light,
      primary: brandOrange,
      secondary: brandBlue,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brandOrange,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
    );
  }
}
