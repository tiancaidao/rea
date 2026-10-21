import 'package:flutter/material.dart';

/// Design tokens for a calm, nocturnal look. Centralizing these is the first
/// step toward a consistent visual identity (one of the UX gaps vs. a polished
/// product).
class AppTheme {
  static const Color bg = Color(0xFF0E1026);
  static const Color surface = Color(0xFF1A1E3A);
  static const Color surfaceHi = Color(0xFF26306A);
  static const Color primary = Color(0xFF6C7BFF);
  static const Color accent = Color(0xFF8C9EFF);
  static const Color rem = Color(0xFF8C9EFF);
  static const Color light = Color(0xFF6C7BFF);
  static const Color deep = Color(0xFF3949AB);
  static const Color awake = Color(0xFFFF8A80);

  static const LinearGradient nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF131A3A), Color(0xFF0A0B1C)],
  );

  static const Map<String, Color> phaseColors = {
    'awake': awake,
    'rem': rem,
    'light': light,
    'deep': deep,
  };

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: bg,
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
