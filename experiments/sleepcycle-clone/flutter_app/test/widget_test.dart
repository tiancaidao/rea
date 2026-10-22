import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sleep_tracker/app_state.dart';
import 'package:sleep_tracker/theme.dart';
import 'package:sleep_tracker/ui/main_shell.dart';

Widget _app() => MaterialApp(theme: buildTheme(AppThemeId.midnight.palette), home: const MainShell());

void main() {
  testWidgets('five tabs in the original order', (tester) async {
    await tester.pumpWidget(_app());
    for (final label in ['Sleep', 'Programs', 'Journal', 'Statistics', 'Profile']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('Profile › More › Database seeds sample nights into Journal', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    AppState.I.eraseAll();

    await tester.pumpWidget(_app());
    AppState.I.goTab(4);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Database'), 200);
    await tester.tap(find.text('Database'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load sample nights (prototype)'));
    await tester.pump();
    expect(AppState.I.nights.length, 7);
  });
}
