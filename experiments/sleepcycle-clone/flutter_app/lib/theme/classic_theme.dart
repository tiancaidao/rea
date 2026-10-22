import 'package:flutter/material.dart';
import 'palette.dart';

/// The app's original look: deep teal night sky, cyan accents and a warm
/// "sunrise" orange call to action.
const classicPalette = SleepPalette(
  brightness: Brightness.dark,
  fontFamily: 'Roboto', // Material default; iOS falls back to the system font
  bg: Color(0xFF071620),
  backdrop: [Color(0xFF0F2B3A), Color(0xFF071620)],
  glow: Color(0x333FC1E0),
  stars: Color(0xFF6FD6FF),
  surface: Color(0xFF102633),
  surfaceHi: Color(0xFF1C3A4A),
  sheet: Color(0xFF0E2230),
  stroke: Color(0x00000000),
  divider: Color(0x1FFFFFFF),
  radius: 14,
  text: Colors.white,
  textMuted: Color(0x99FFFFFF),
  textFaint: Color(0x61FFFFFF),
  accent: Color(0xFF7FE1E8),
  cta: [Color(0xFFFF8A4C)],
  onCta: Colors.white,
  warn: Color(0xFFE8B04A),
  positive: Color(0xFF69F0AE),
  nav: Color(0xFF0A1B26),
  navIdle: Color(0xFF5F8396),
  segTrack: Color(0xFF102633),
  segThumb: Color(0xFF2A5C70),
  segThumbText: Colors.white,
  deep: Color(0xFF28407A),
  light: Color(0xFF4F7BD6),
  rem: Color(0xFF7FB8FF),
  awake: Color(0xFFFFB27A),
  quality: Color(0xFFD08A2E),
  chart: Color(0xFF2C7F98),
  chartAlt: Color(0xFF7FA6B8),
);
