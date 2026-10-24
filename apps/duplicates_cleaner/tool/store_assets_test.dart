// Renders the App Store and Google Play listing images: captioned
// screenshots for every required device size, the app icon and the Play
// feature graphic.
//
//   flutter test tool/store_assets_test.dart
//
// Output lands in build/store_assets/. Lives under tool/ so the regular
// `flutter test` run skips it. The results screen runs a real scan over
// sample photos written to /var/mobile/Documents (iOS shots) and
// /storage/emulated/0 (Android shots), so the paths read like a device's;
// run it somewhere those paths are writable, such as a container.
//
// Captions use Plus Jakarta Sans (OFL), which isn't checked in. Download
// PlusJakartaSans[wght].ttf from github.com/google/fonts (ofl/plusjakartasans)
// to tool/PlusJakartaSans.ttf, or point STORE_DISPLAY_FONT at it.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duplicates_cleaner/app.dart';
import 'package:duplicates_cleaner/models/enums.dart';
import 'package:duplicates_cleaner/screens/home_screen.dart';
import 'package:duplicates_cleaner/screens/onboarding_screen.dart';
import 'package:duplicates_cleaner/screens/paywall_screen.dart';
import 'package:duplicates_cleaner/screens/scanner_screen.dart';
import 'package:duplicates_cleaner/screens/settings_screen.dart';
import 'package:duplicates_cleaner/services/premium_service.dart';
import 'package:duplicates_cleaner/services/settings_store.dart';
import 'package:duplicates_cleaner/services/storage_service.dart';
import 'package:duplicates_cleaner/widgets/themed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/store_assets';
const _display = 'Jakarta';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  // Roboto also stands in for the iOS system font, which can't be bundled.
  for (final family in [
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.SF UI Text',
    '.SF UI Display',
  ]) {
    await _loadFont(family, [
      for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
    ]);
  }
  // Plus Jakarta Sans (OFL), variable weight, for captions.
  await _loadFont(_display, [
    Platform.environment['STORE_DISPLAY_FONT'] ?? 'tool/PlusJakartaSans.ttf',
  ]);
}

/// A device the listing needs images for.
class Device {
  const Device(
    this.id,
    this.canvas,
    this.screen, {
    required this.ios,
    this.tablet = false,
  });

  final String id;

  /// Output size in pixels.
  final Size canvas;

  /// The device's logical screen size, which the app is laid out at.
  final Size screen;
  final bool ios;
  final bool tablet;

  EdgeInsets get safeArea => ios
      ? (tablet
            ? const EdgeInsets.only(top: 24, bottom: 20)
            : const EdgeInsets.only(top: 62, bottom: 34))
      : const EdgeInsets.only(top: 28, bottom: 16);
}

const devices = [
  Device('ios_iphone_6.9', Size(1320, 2868), Size(440, 956), ios: true),
  Device('ios_iphone_6.5', Size(1284, 2778), Size(428, 926), ios: true),
  Device('ios_iphone_6.3', Size(1206, 2622), Size(402, 874), ios: true),
  Device(
    'ios_ipad_13',
    Size(2064, 2752),
    Size(1032, 1376),
    ios: true,
    tablet: true,
  ),
  Device('android_phone', Size(1080, 1920), Size(412, 840), ios: false),
  Device(
    'android_tablet_10',
    Size(1600, 2560),
    Size(800, 1280),
    ios: false,
    tablet: true,
  ),
];

/// Reports the sample folder as the scan root on any platform.
class _SampleStorage extends StorageService {
  _SampleStorage(this.root);
  final String root;

  @override
  Future<bool> ensureAccess() async => true;

  @override
  Future<List<String>> rootsFor(
    StorageSelection s, {
    String? customFolder,
  }) async => [root];
}

// ---------------------------------------------------------------------------
// Sample data

img.Image _photo(int seed) {
  final r = math.Random(seed);
  const w = 1200, h = 900;
  final im = img.Image(width: w, height: h);
  final top = [40 + r.nextInt(80), 110 + r.nextInt(70), 200 + r.nextInt(50)];
  final bottom = [
    230 + r.nextInt(25),
    160 + r.nextInt(60),
    110 + r.nextInt(70),
  ];
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final c = [for (var i = 0; i < 3; i++) (top[i] * (1 - t) + bottom[i] * t)];
    img.drawLine(
      im,
      x1: 0,
      y1: y,
      x2: w - 1,
      y2: y,
      color: img.ColorRgb8(c[0].round(), c[1].round(), c[2].round()),
    );
  }
  img.fillCircle(
    im,
    x: (w * (0.55 + r.nextDouble() * 0.25)).round(),
    y: (h * (0.22 + r.nextDouble() * 0.1)).round(),
    radius: 70,
    color: img.ColorRgb8(255, 238, 190),
  );
  for (var layer = 0; layer < 3; layer++) {
    final base = h * (0.5 + layer * 0.13);
    final shade = 40 * layer;
    final col = img.ColorRgb8(
      math.max(0, 50 + r.nextInt(40) - shade),
      math.max(0, 100 + r.nextInt(50) - shade),
      math.max(0, 90 + r.nextInt(40) - shade),
    );
    final pts = <img.Point>[img.Point(0, h)];
    for (var x = 0; x <= w + 80; x += 80) {
      pts.add(img.Point(x, base - r.nextInt((h * 0.18).round())));
    }
    pts.add(img.Point(w, h));
    img.fillPolygon(im, vertices: pts, color: col);
  }
  return img.gaussianBlur(im, radius: 2);
}

/// Writes sets of identical photos, each padded to a camera-like size.
void _writeSamples(String root) {
  final dir = Directory(root);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final sets = [
    (
      [
        'DCIM/IMG_2041.jpg',
        'DCIM/IMG_2041 (1).jpg',
        'WhatsApp/IMG-20260914-WA0007.jpg',
      ],
      3412000,
    ),
    (['DCIM/IMG_1876.jpg', 'DCIM/IMG_1876 copy.jpg'], 2874000),
    (
      ['DCIM/IMG_3310.jpg', 'Download/IMG_3310.jpg', 'DCIM/IMG_3310 (2).jpg'],
      4105000,
    ),
    (['DCIM/IMG_0917.jpg', 'Backup/IMG_0917.jpg'], 2236000),
    (['DCIM/IMG_2288.jpg', 'DCIM/IMG_2288 (1).jpg'], 3018000),
  ];
  // A modified time shared by every sample, so dates read the same.
  final when = DateTime(2026, 9, 14, 18, 32);
  for (final (i, (names, size)) in sets.indexed) {
    final jpg = img.encodeJpg(_photo(i * 13 + 5), quality: 90);
    final padded = Uint8List(size)..setAll(0, jpg);
    for (var b = jpg.length; b < size; b++) {
      padded[b] = (b * 31 + i) & 0xff;
    }
    for (final n in names) {
      final f = File('$root/$n')..createSync(recursive: true);
      f.writeAsBytesSync(padded);
      f.setLastModifiedSync(when);
    }
  }
}

// ---------------------------------------------------------------------------
// Frames

/// A device's status bar, drawn so screenshots look like the real thing.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final ios = device.ios;
    const style = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
      fontFamily: 'Roboto',
    );
    return SizedBox(
      height: device.safeArea.top,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ios ? 34 : 20),
        child: Row(
          children: [
            Text(ios ? '9:41' : '12:00', style: style),
            const Spacer(),
            const Icon(
              Icons.signal_cellular_alt,
              size: 17,
              color: AppColors.text,
            ),
            const SizedBox(width: 5),
            const Icon(Icons.wifi, size: 17, color: AppColors.text),
            const SizedBox(width: 5),
            const Icon(Icons.battery_full, size: 18, color: AppColors.text),
          ],
        ),
      ),
    );
  }
}

/// The app's theme with an explicit font on the styles that name none. On
/// a device those fall back to the system font; in tests to a box font.
ThemeData _deviceTheme(Device device) {
  final t = buildAppTheme();
  TextStyle? roboto(TextStyle? s) => s?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? button(ButtonStyle? s) => s?.copyWith(
    textStyle: s.textStyle == null
        ? null
        : WidgetStatePropertyAll(roboto(s.textStyle!.resolve({}))),
  );
  return t.copyWith(
    platform: device.ios ? TargetPlatform.iOS : TargetPlatform.android,
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle: roboto(t.appBarTheme.titleTextStyle),
    ),
    listTileTheme: t.listTileTheme.copyWith(
      subtitleTextStyle: roboto(t.listTileTheme.subtitleTextStyle),
    ),
    dialogTheme: t.dialogTheme.copyWith(
      titleTextStyle: roboto(t.dialogTheme.titleTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(t.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(t.outlinedButtonTheme.style),
    ),
  );
}

/// The app at the device's logical size, with its own navigator.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.device,
    required this.scope,
    required this.navigator,
    required this.home,
  });

  final Device device;
  final AppScope Function(Widget) scope;
  final GlobalKey<NavigatorState> navigator;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final size = device.screen;
    return SizedBox.fromSize(
      size: size,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 3,
          padding: device.safeArea,
          viewPadding: device.safeArea,
        ),
        child: Stack(
          children: [
            scope(
              MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: _deviceTheme(device),
                home: home,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _StatusBar(device: device),
            ),
            if (device.ios)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: Container(
                    width: device.tablet ? 320 : 140,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.text,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A captioned store image: headline on the blue wash, the app in a device.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.device,
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final Device device;
  final String title;
  final String subtitle;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    final w = device.canvas.width, h = device.canvas.height;
    // Text scales with the canvas width, capped for wide tablets.
    final unit = math.min(w, h * 0.62) / 100;
    final bezel = device.screen.width * (device.tablet ? 0.022 : 0.04);
    final radius = device.tablet ? 36.0 : (device.ios ? 58.0 : 40.0);
    final framed = Container(
      padding: EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A2E),
        borderRadius: BorderRadius.circular(radius + bezel),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDeep.withValues(alpha: 0.35),
            blurRadius: 80,
            offset: const Offset(0, 30),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: screen,
      ),
    );
    return Container(
      width: w,
      height: h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2F8CFF), Color(0xFF0A62E8), Color(0xFF0750C4)],
        ),
      ),
      child: Stack(
        children: [
          // Soft light circles behind the device.
          Positioned(
            left: -w * 0.25,
            top: h * 0.32,
            child: _Glow(size: w * 0.9),
          ),
          Positioned(
            right: -w * 0.3,
            bottom: -h * 0.05,
            child: _Glow(size: w * 0.8),
          ),
          Column(
            children: [
              SizedBox(height: h * 0.055),
              // Fixed caption height, so every device sits at the same spot.
              Container(
                height: unit * 31,
                alignment: Alignment.topCenter,
                padding: EdgeInsets.symmetric(horizontal: w * 0.08),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _display,
                        fontVariations: const [ui.FontVariation('wght', 800)],
                        fontSize: unit * 8.2,
                        height: 1.12,
                        letterSpacing: -unit * 0.15,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: unit * 2.6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _display,
                        fontVariations: const [ui.FontVariation('wght', 500)],
                        fontSize: unit * 4.1,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: h * 0.04),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: h * 0.045),
                  child: FittedBox(child: framed),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

/// The app icon: the brand mark on a pale blue tile. Full bleed and opaque,
/// as the stores require; [inset] shrinks the mark for adaptive icons.
class StoreIcon extends StatelessWidget {
  const StoreIcon({
    super.key,
    this.size = 1024,
    this.inset = 1,
    this.background = true,
  });

  final double size;
  final double inset;
  final bool background;

  @override
  Widget build(BuildContext context) {
    final mark = size * 0.7 * inset;
    return Container(
      width: size,
      height: size,
      decoration: background
          ? const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4F9FF), Color(0xFFCFE3FD)],
              ),
            )
          : null,
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(0, -mark * 0.06),
        child: AppMark(size: mark),
      ),
    );
  }
}

/// Play's 1024 x 500 feature graphic.
class FeatureGraphic extends StatelessWidget {
  const FeatureGraphic({super.key, required this.phone});
  final Widget phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1024,
      height: 500,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F8CFF), Color(0xFF0750C4)],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(left: -120, top: -160, child: _Glow(size: 560)),
          Positioned(
            left: 64,
            top: 0,
            bottom: 0,
            width: 560,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: const StoreIcon(size: 112),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Duplicate Sweep',
                  style: TextStyle(
                    fontFamily: _display,
                    fontVariations: [ui.FontVariation('wght', 800)],
                    fontSize: 52,
                    letterSpacing: -1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Find and remove duplicate photos, music,\n'
                  'videos and documents.',
                  style: TextStyle(
                    fontFamily: _display,
                    fontVariations: const [ui.FontVariation('wght', 500)],
                    fontSize: 24,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 70,
            top: 60,
            child: Transform.rotate(
              angle: 0.08,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1A2E),
                  borderRadius: BorderRadius.circular(46),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55001A4D),
                      blurRadius: 50,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: SizedBox(
                    width: 300,
                    height: 612,
                    child: FittedBox(fit: BoxFit.cover, child: phone),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Capture

final _boundary = GlobalKey();

Future<void> _settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _save(
  WidgetTester tester,
  String path, {
  bool opaque = true,
}) async {
  await tester.runAsync(() async {
    final ro =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    var png = bytes!.buffer.asUint8List();
    if (opaque) {
      // App Store Connect rejects images with an alpha channel.
      final decoded = img.decodePng(png)!;
      png = img.encodePng(decoded.convert(numChannels: 3));
    }
    File('$_out/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
  });
}

class _Shot {
  const _Shot(this.name, this.title, this.subtitle, this.build);

  final String name;
  final String title;
  final String subtitle;

  /// Sets up the screen: returns the home widget and an optional step run
  /// after the first frame (navigation, taps, waiting for a scan).
  final (Widget, Future<void> Function(WidgetTester, NavigatorState)?)
  Function()
  build;
}

void main() {
  setUpAll(_loadFonts);

  late SettingsStore settings;
  late PremiumService premium;

  Future<void> resetPrefs() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'FirstLaunch': false,
      'DeletionSuccessCount': 1284,
    });
    settings = await SettingsStore.load();
    premium = await PremiumService.load();
  }

  Future<void> push(WidgetTester t, NavigatorState nav, Widget screen) async {
    nav.push(MaterialPageRoute<void>(builder: (_) => screen));
    await _settle(t, frames: 12);
  }

  final shots = [
    _Shot(
      '1_home',
      'Free up space\nin one tap',
      'Find and delete duplicate files fast',
      () => (const HomeScreen(), null),
    ),
    _Shot(
      '2_results',
      'Find exact\nduplicate photos',
      'Matched by content, not by file name',
      () => (
        const HomeScreen(),
        (t, nav) async {
          await push(t, nav, const ScannerScreen(scanType: ScanType.image));
          // The scan runs on a real isolate and reads real files.
          for (var i = 0; i < 20; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 250)),
            );
            await t.pump(const Duration(milliseconds: 50));
          }
          await _settle(t);
          // Let the thumbnails decode.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          await _settle(t);
        },
      ),
    ),
    _Shot(
      '3_categories',
      'Scan every\nfile type',
      'Photos, music, videos, docs and more',
      () => (
        const OnboardingScreen(),
        (t, nav) async {
          await t.tap(find.text('Continue'));
          await _settle(t);
        },
      ),
    ),
    _Shot(
      '4_control',
      'The original\nis always kept',
      'Preview every file before you clean',
      () => (
        const OnboardingScreen(),
        (t, nav) async {
          for (var i = 0; i < 3; i++) {
            await t.tap(find.text('Continue'));
            await _settle(t);
          }
        },
      ),
    ),
    _Shot(
      '5_settings',
      'Tune every\nscan your way',
      'Folders, match type and size filters',
      () => (
        const HomeScreen(),
        (t, nav) => push(t, nav, const SettingsScreen()),
      ),
    ),
    _Shot(
      '6_prime',
      'Go Prime\nfor no limits',
      'Unlimited cleaning, pay once or monthly',
      () => (const PaywallScreen(), null),
    ),
  ];

  for (final device in devices) {
    for (final shot in shots) {
      testWidgets('${device.id} ${shot.name}', (tester) async {
        await resetPrefs();
        final sampleRoot = device.ios
            ? '/var/mobile/Documents'
            : '/storage/emulated/0';
        if (shot.name == '2_results') _writeSamples(sampleRoot);
        tester.view.physicalSize = device.canvas;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final nav = GlobalKey<NavigatorState>();
        final (home, after) = shot.build();
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _Poster(
                device: device,
                title: shot.title,
                subtitle: shot.subtitle,
                screen: _Screen(
                  device: device,
                  navigator: nav,
                  home: home,
                  scope: (child) => AppScope(
                    settings: settings,
                    premium: premium,
                    storage: _SampleStorage(sampleRoot),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
        await _settle(tester);
        if (after != null) await after(tester, nav.currentState!);
        await _settle(tester);
        await _save(tester, '${device.id}/${shot.name}.png');
      });
    }
  }

  testWidgets('app icon', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> render(Widget w, String path, {bool opaque = true}) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: Directionality(textDirection: TextDirection.ltr, child: w),
        ),
      );
      await _settle(tester, frames: 2);
      await _save(tester, path, opaque: opaque);
    }

    await render(const Center(child: StoreIcon()), 'icon/icon_1024.png');
    // Adaptive icon foreground: the mark inside the 66/108 safe zone.
    await render(
      const Center(child: StoreIcon(inset: 0.66, background: false)),
      'icon/icon_foreground_1024.png',
      opaque: false,
    );
  });

  testWidgets('feature graphic', (tester) async {
    await resetPrefs();
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const device = Device(
      'feature',
      Size(1024, 500),
      Size(412, 840),
      ios: false,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FeatureGraphic(
            phone: _Screen(
              device: device,
              navigator: GlobalKey<NavigatorState>(),
              home: const HomeScreen(),
              scope: (child) => AppScope(
                settings: settings,
                premium: premium,
                storage: _SampleStorage('/storage/emulated/0'),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    await _save(tester, 'android/feature_graphic_1024x500.png');
  });
}
