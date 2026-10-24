import 'package:duplicates_cleaner/app.dart';
import 'package:duplicates_cleaner/core/constants.dart';
import 'package:duplicates_cleaner/screens/home_screen.dart';
import 'package:duplicates_cleaner/screens/onboarding_screen.dart';
import 'package:duplicates_cleaner/screens/paywall_screen.dart';
import 'package:duplicates_cleaner/services/premium_service.dart';
import 'package:duplicates_cleaner/services/settings_store.dart';
import 'package:duplicates_cleaner/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsStore settings;
  late PremiumService premium;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.load();
    premium = await PremiumService.load();
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        settings: settings,
        premium: premium,
        storage: StorageService(),
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ),
    );
  }

  // Illustrations animate forever, so settle with fixed frames.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('onboarding walks through to the paywall, then home', (
    tester,
  ) async {
    await pumpApp(tester, const OnboardingScreen());
    expect(find.text('Duplicates Cleaner'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Continue'));
      await frames(tester);
    }
    expect(find.text('You stay in control'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await frames(tester);

    expect(settings.firstLaunch, isFalse);
    expect(find.byType(PaywallScreen), findsOneWidget);
    await tester.tap(find.text('Continue with the free version'));
    await frames(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('paywall shows the free limits and switches plans', (
    tester,
  ) async {
    await pumpApp(tester, const PaywallScreen(reason: 'Limit reached.'));
    await frames(tester);
    expect(find.text('Limit reached.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('< 500 MB'), 200);
    expect(
      find.text('${AppConstants.freeDeleteMaxFilesPerOperation}'),
      findsOneWidget,
    );
    expect(find.text('< 500 MB'), findsOneWidget);
    expect(find.text('Unlock Prime for \$9.99'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await frames(tester);
    expect(find.text('Start Prime for \$1.99/month'), findsOneWidget);
  });

  testWidgets('purchasing unlocks premium and closes the paywall', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await frames(tester);
    await tester.tap(find.text('Unlock Prime for \$9.99'));
    await frames(tester);
    expect(premium.isPremium, isTrue);
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
