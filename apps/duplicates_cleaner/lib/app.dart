import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/premium_service.dart';
import 'services/settings_store.dart';
import 'services/storage_service.dart';
import 'theme.dart';

export 'theme.dart';

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
  const DuplicatesCleanerApp({
    super.key,
    required this.settings,
    required this.premium,
  });

  final SettingsStore settings;
  final PremiumService premium;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      premium: premium,
      storage: StorageService(),
      child: MaterialApp(
        title: 'Duplicate Sweep',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: settings.firstLaunch
            ? const OnboardingScreen()
            : const HomeScreen(),
      ),
    );
  }
}
