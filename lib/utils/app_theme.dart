import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF059669); // Bangladesh Railway emerald green
  static const Color appBarGreen = Color(0xFF065F46); // Deep emerald for app bar
  static const Color accentCyan = Color(0xFF0D9488);
  static const Color amberWarning = Color(0xFFD97706);

  static Color scaffoldBg(bool isDark) =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

  static Color cardBg(bool isDark) =>
      isDark ? const Color(0xFF1E293B) : Colors.white;

  static Color cardBorder(bool isDark) =>
      isDark ? Colors.white12 : const Color(0xFFE2E8F0);

  static Color textPrimary(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF0F172A);

  static Color textSecondary(bool isDark) =>
      isDark ? Colors.white70 : const Color(0xFF475569);

  static Color textMuted(bool isDark) =>
      isDark ? Colors.white38 : const Color(0xFF94A3B8);

  static Color inputFill(bool isDark) =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  static Color inputBorder(bool isDark) =>
      isDark ? Colors.white12 : const Color(0xFFCBD5E1);

  static Color bannerBg(bool isDark) =>
      isDark ? const Color(0xFF1E293B) : Colors.white;
}

class AppThemes {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF1F5F9),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF059669),
      secondary: Color(0xFF0D9488),
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: Color(0xFF0F172A),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF065F46),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
    useMaterial3: true,
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF10B981),
      secondary: Color(0xFF06B6D4),
      surface: Color(0xFF1E293B),
      onPrimary: Colors.white,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF065F46),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E293B),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
    ),
    useMaterial3: true,
  );
}
