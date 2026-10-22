import 'package:flutter/material.dart';
import 'palette.dart';

/// Daylight companion to Midnight: misty sage-grey air, frosted white cards
/// and deep forest-ink text. Stages run forest → sage → mint, with a
/// terracotta coral for awake moments.
const mistPalette = SleepPalette(
  brightness: Brightness.light,
  fontFamily: 'DMSans',
  bg: Color(0xFFE6ECEA),
  backdrop: [Color(0xFFF1F4F2), Color(0xFFD7E0DD)],
  glow: Color(0x55A9C8BE),
  stars: null,
  surface: Color(0xCCFFFFFF),
  surfaceHi: Color(0xFFFFFFFF),
  sheet: Color(0xFFF4F6F5),
  stroke: Color(0xB3FFFFFF),
  divider: Color(0x1A1E2A28),
  radius: 26,
  text: Color(0xFF1C2826),
  textMuted: Color(0xFF5F6D6A),
  textFaint: Color(0xFF9AA5A2),
  accent: Color(0xFF2F5A50),
  cta: [Color(0xFF2B403B)],
  onCta: Color(0xFFF4F6F5),
  warn: Color(0xFFC9803C),
  positive: Color(0xFF3F8A6A),
  nav: Color(0xF2FFFFFF),
  navIdle: Color(0xFF9AA5A2),
  segTrack: Color(0x99FFFFFF),
  segThumb: Color(0xFF2B403B),
  segThumbText: Color(0xFFF4F6F5),
  deep: Color(0xFF2F5249),
  light: Color(0xFF6E9488),
  rem: Color(0xFFA9CCC0),
  awake: Color(0xFFD9826A),
  quality: Color(0xFF3E6359),
  chart: Color(0xFF4F7A6F),
  chartAlt: Color(0xFF8DB3A7),
);
