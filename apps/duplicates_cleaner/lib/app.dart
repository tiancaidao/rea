import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/tutorial_screen.dart';
import 'services/premium_service.dart';
import 'services/settings_store.dart';
import 'services/storage_service.dart';

/// Colours from the original resources (colorPrimary, colorAccent, colorFill).
class AppColors {
  static const primary = Color(0xFFFFD046);
  static const primaryDark = Color(0xFFFFBD21);
  static const accent = Color(0xFF3498DB);
  static const background = Color(0xFFFDF8F2);
  static const panel = Color(0xFFF5F5F5);
  static const lightBlack = Color(0xFF4C4C4C);
}

/// Simple service locator handed down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.premium,
    required this.storage,
    required super.child,
  });

  final SettingsStore settings;
  final PremiumService premium;
  final StorageService storage;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

class DuplicatesCleanerApp extends StatelessWidget {
  const DuplicatesCleanerApp({super.key, required this.settings, required this.premium});

  final SettingsStore settings;
  final PremiumService premium;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primaryDark,
      secondary: AppColors.accent,
      surface: AppColors.background,
    );
    return AppScope(
      settings: settings,
      premium: premium,
      storage: StorageService(),
      child: MaterialApp(
        title: 'Duplicates Cleaner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          scaffoldBackgroundColor: AppColors.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.background,
            foregroundColor: Colors.black,
            elevation: 0,
            centerTitle: true,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
        home: settings.firstLaunch ? const TutorialScreen() : const HomeScreen(),
      ),
    );
  }
}
