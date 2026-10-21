import 'package:flutter/material.dart';

/// Design tokens for a calm, nocturnal look. Centralizing these is the first
/// step toward a consistent visual identity (one of the UX gaps vs. a polished
/// product).
class AppTheme {
  // A deep-navy base with a teal brand accent and a warm "sunrise" button
  // color — a deliberate identity, not Flutter's default purple. Our own
  // palette (close in spirit to a calm sleep app without copying any brand).
  static const Color bg = Color(0xFF0B1020);
  static const Color surface = Color(0xFF151B33);
  static const Color surfaceHi = Color(0xFF223055);
  static const Color primary = Color(0xFF3FB4C4); // teal brand accent
  static const Color accent = Color(0xFF7FE1E8);
  static const Color cta = Color(0xFFFF8A4C); // warm sunrise button
  static const Color rem = Color(0xFF7FB8FF);
  static const Color light = Color(0xFF4F7BD6);
  static const Color deep = Color(0xFF28407A);
  static const Color awake = Color(0xFFFFB27A);

  static const LinearGradient nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17213F), Color(0xFF080B18)],
  );

  static const Map<String, Color> phaseColors = {
    'awake': awake,
    'rem': rem,
    'light': light,
    'deep': deep,
  };

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      surface: surface,
      primary: primary,
      secondary: accent,
      // route the warm CTA through tertiary so FilledButtons pick it up
      tertiary: cta,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cta,
          foregroundColor: const Color(0xFF1A1206),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withOpacity(0.22),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
