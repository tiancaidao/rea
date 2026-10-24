import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sleep_tracker/paywall/paywall_config.dart';
import 'package:sleep_tracker/paywall/paywall_screen.dart';
import 'package:sleep_tracker/theme.dart';

void main() {
  final cfg = jsonDecode(File('assets/paywalls.json').readAsStringSync()) as Map<String, dynamic>;

  test('local choice is sticky, weighted and reaches every onboarding variant', () {
    final a = Paywalls.choose(cfg, Placement.onboarding, 'install-1', null)!['variant'];
    expect(Paywalls.choose(cfg, Placement.onboarding, 'install-1', null)!['variant'], a);
    final seen = {for (var i = 0; i < 500; i++) Paywalls.choose(cfg, Placement.onboarding, 'x$i', null)!['variant']};
    expect(seen.length, (cfg['placements']['onboarding']['variants'] as List).length);
    expect(Paywalls.choose(cfg, Placement.appOpen, 'x', null), isNull);
    expect(Paywalls.choose(cfg, Placement.inApp, 'x', 'gift_cards')!['variant'], 'gift_cards');
  });

  for (final id in (cfg['variants'] as Map).keys) {
    testWidgets('variant $id renders every module without errors', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(AppThemeId.midnight.palette),
          home: PaywallScreen(placement: Placement.inApp, variant: id)));
      await tester.pumpAndSettle();
      final modules = (cfg['variants'][id]['modules'] as List).map((m) => m['type']).toSet();
      expect(find.byType(ListView), findsOneWidget);
      if (modules.contains('pricing')) {
        await tester.scrollUntilVisible(find.textContaining('Cancel anytime'), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Cancel anytime'), findsWidgets);
      }
    });
  }
}
