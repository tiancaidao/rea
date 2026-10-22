import 'package:flutter/material.dart';
import 'classic_theme.dart';
import 'midnight_theme.dart';
import 'mist_theme.dart';
import 'palette.dart';

/// The themes a user can pick in Profile › Theme. The label doubles as the
/// stored preference value.
enum AppThemeId {
  midnight('Midnight', 'Dark glass with a blue stage gradient', midnightPalette),
  mist('Mist', 'Light, misty sage with frosted cards', mistPalette),
  classic('Classic', 'The original teal night sky', classicPalette);

  final String label;
  final String blurb;
  final SleepPalette palette;
  const AppThemeId(this.label, this.blurb, this.palette);

  static AppThemeId byLabel(String label) =>
      values.firstWhere((t) => t.label == label, orElse: () => midnight);
}

/// Builds Material [ThemeData] from a palette so built-in widgets (buttons,
/// sheets, chips, switches) follow the active theme too.
ThemeData buildTheme(SleepPalette p) {
  final dark = p.isDark;
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    primary: p.accent,
    onPrimary: dark ? Colors.black : Colors.white,
    secondary: p.accent,
    tertiary: p.cta.first,
    outlineVariant: p.divider,
    surfaceContainerHighest: p.surfaceHi,
  );
  final base = ThemeData(useMaterial3: true, brightness: p.brightness, fontFamily: p.fontFamily);
  final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text, fontFamily: p.fontFamily);
  return base.copyWith(
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.divider,
    dividerTheme: DividerThemeData(color: p.divider),
    iconTheme: IconThemeData(color: p.accent),
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.radius), side: BorderSide(color: p.stroke)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(p.radius))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.sheet, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceHi,
      contentTextStyle: TextStyle(color: p.text, fontFamily: p.fontFamily),
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.surfaceHi,
      labelStyle: TextStyle(color: p.text, fontFamily: p.fontFamily),
      side: BorderSide(color: p.stroke),
      shape: const StadiumBorder(),
    ),
    listTileTheme: ListTileThemeData(textColor: p.text, iconColor: p.accent),
    switchTheme: SwitchThemeData(
      thumbColor:
          WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onCta : p.textFaint),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.cta.first : p.surfaceHi),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.accent)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.cta.first,
        foregroundColor: p.onCta,
        shape: const StadiumBorder(),
        textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, fontFamily: p.fontFamily),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.nav,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.accent : p.navIdle)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: p.fontFamily,
            color: s.contains(WidgetState.selected) ? p.text : p.navIdle,
          )),
    ),
  );
}
