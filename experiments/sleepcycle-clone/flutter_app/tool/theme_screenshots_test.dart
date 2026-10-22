// Renders the main screens in every theme to PNGs for design review:
//
//   flutter test tool/theme_screenshots_test.dart
//
// Output lands in build/theme_screenshots/<theme>_<screen>.png. Lives under
// tool/ so the regular `flutter test` run skips it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sleep_tracker/app_state.dart';
import 'package:sleep_tracker/theme.dart';
import 'package:sleep_tracker/ui/main_shell.dart';
import 'package:sleep_tracker/ui/settings_pages.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await _loadFont('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
  ]);
  await _loadFont('DMSans', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/DMSans-$w.ttf',
  ]);
}

final _boundary = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final ro = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/theme_screenshots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  for (final theme in AppThemeId.values) {
    testWidgets('screens in ${theme.label}', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      AppState.I.eraseAll();
      AppState.I.loadSampleNights();
      AppState.I.setPref('theme', theme.label);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          navigatorKey: nav,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(theme.palette),
          home: const MainShell(),
        ),
      ));
      final id = theme.name;

      AppState.I.goTab(0);
      await _shot(tester, '${id}_1_sleep');
      AppState.I.goTab(2);
      await _shot(tester, '${id}_2_journal');
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await _shot(tester, '${id}_3_journal_tiles');
      AppState.I.goTab(3);
      await _shot(tester, '${id}_4_stats');
      AppState.I.goTab(4);
      nav.currentState!.push(MaterialPageRoute(builder: (_) => const ThemePage()));
      await _shot(tester, '${id}_5_theme_picker');
    });
  }
}
