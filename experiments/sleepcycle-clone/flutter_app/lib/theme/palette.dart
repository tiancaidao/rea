import 'package:flutter/material.dart';

/// Every color, radius and font a screen may use. Each theme file supplies
/// one const [SleepPalette]; widgets read it with `context.palette` so a
/// theme switch repaints the whole app without touching screen code.
@immutable
class SleepPalette extends ThemeExtension<SleepPalette> {
  final Brightness brightness;
  final String? fontFamily;

  // ── backdrop ──────────────────────────────────────────────────────────────
  final Color bg; // scaffold
  final List<Color> backdrop; // top → bottom gradient behind hero screens
  final Color glow; // soft radial bloom behind the hero (ring, clock)
  final Color? stars; // null = no star field

  // ── surfaces ──────────────────────────────────────────────────────────────
  final Color surface; // cards and tiles
  final Color surfaceHi; // pressed / selected / chips
  final Color sheet; // bottom sheets and dialogs
  final Color stroke; // hairline card borders
  final Color divider;
  final double radius; // card corner radius

  // ── text ──────────────────────────────────────────────────────────────────
  final Color text;
  final Color textMuted;
  final Color textFaint;

  // ── brand ─────────────────────────────────────────────────────────────────
  final Color accent; // icons, links, active states
  final List<Color> cta; // primary button fill (1 color = solid, 2 = gradient)
  final Color onCta;
  final Color warn;
  final Color positive;

  // ── navigation ────────────────────────────────────────────────────────────
  final Color nav;
  final Color navIdle;
  final Color segTrack; // segmented-pill track
  final Color segThumb; // segmented-pill selected thumb
  final Color segThumbText;

  // ── data ──────────────────────────────────────────────────────────────────
  final Color deep;
  final Color light;
  final Color rem;
  final Color awake;
  final Color quality; // score ring / quality bars
  final Color chart; // default bar color
  final Color chartAlt; // line charts

  const SleepPalette({
    required this.brightness,
    this.fontFamily,
    required this.bg,
    required this.backdrop,
    required this.glow,
    this.stars,
    required this.surface,
    required this.surfaceHi,
    required this.sheet,
    required this.stroke,
    required this.divider,
    this.radius = 22,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.cta,
    required this.onCta,
    required this.warn,
    required this.positive,
    required this.nav,
    required this.navIdle,
    required this.segTrack,
    required this.segThumb,
    required this.segThumbText,
    required this.deep,
    required this.light,
    required this.rem,
    required this.awake,
    required this.quality,
    required this.chart,
    required this.chartAlt,
  });

  bool get isDark => brightness == Brightness.dark;

  Map<String, Color> get phaseColors => {'awake': awake, 'rem': rem, 'light': light, 'deep': deep};
  Color phase(String p) => phaseColors[p] ?? light;

  Gradient get ctaGradient => LinearGradient(colors: cta.length == 1 ? [cta[0], cta[0]] : cta);

  @override
  SleepPalette copyWith({Color? accent}) => SleepPalette(
        brightness: brightness,
        fontFamily: fontFamily,
        bg: bg,
        backdrop: backdrop,
        glow: glow,
        stars: stars,
        surface: surface,
        surfaceHi: surfaceHi,
        sheet: sheet,
        stroke: stroke,
        divider: divider,
        radius: radius,
        text: text,
        textMuted: textMuted,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        cta: cta,
        onCta: onCta,
        warn: warn,
        positive: positive,
        nav: nav,
        navIdle: navIdle,
        segTrack: segTrack,
        segThumb: segThumb,
        segThumbText: segThumbText,
        deep: deep,
        light: light,
        rem: rem,
        awake: awake,
        quality: quality,
        chart: chart,
        chartAlt: chartAlt,
      );

  // Themes swap wholesale, so there is nothing meaningful to tween.
  @override
  SleepPalette lerp(SleepPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PaletteContext on BuildContext {
  SleepPalette get palette => Theme.of(this).extension<SleepPalette>()!;
}
