import 'package:flutter/material.dart';

/// Soft light-blue palette: a saturated blue for actions, pale blue washes
/// behind white rounded cards, and pastel tints for the category badges.
class AppColors {
  static const primary = Color(0xFF0A7AFF);
  static const primaryDeep = Color(0xFF0057D9);
  static const primaryLight = Color(0xFF6FB1FF);
  static const background = Color(0xFFEDF3FB);
  static const backgroundTop = Color(0xFFD9E8FB);
  static const surface = Colors.white;
  static const ring = Color(0xFFE6EDF7);
  static const text = Color(0xFF111827);
  static const textMuted = Color(0xFF8A94A6);
  static const shadow = Color(0x1A2F6BDB);
  static const premium = Color(0xFFFFB020);

  /// Badge colours, one per scan category, in [ScanType] order.
  static const badges = [
    Color(0xFF0A7AFF), // images
    Color(0xFF7A80F5), // audio
    Color(0xFFF08A1C), // video
    Color(0xFFD678E8), // docs
    Color(0xFF2EBF7A), // apk
    Color(0xFF3BB4E6), // custom
  ];

  /// Page wash: pale blue at the top fading into the background.
  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background],
  );

  static const buttonGradient = LinearGradient(
    colors: [primaryLight, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadii {
  static const card = 22.0;
  static const sheet = 32.0;
  static const button = 14.0;
}

/// Soft blue drop shadow shared by cards and buttons.
List<BoxShadow> softShadow({double blur = 24, double y = 8, Color? color}) => [
  BoxShadow(
    color: color ?? AppColors.shadow,
    blurRadius: blur,
    offset: Offset(0, y),
  ),
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.primaryLight,
    surface: AppColors.surface,
    onSurface: AppColors.text,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.button),
  );
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppColors.shadow,
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        minimumSize: const Size(64, 52),
        side: BorderSide.none,
        textStyle: buttonText.copyWith(fontWeight: FontWeight.w500),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.primary,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      subtitleTextStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.ring,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: const BorderSide(color: AppColors.textMuted, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : Colors.transparent,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.ring,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.background,
      side: BorderSide.none,
      shape: StadiumBorder(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
  );
}
