import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'backend/backend.dart';
import 'device/notifications.dart';
import 'theme.dart';
import 'strings.dart';
import 'ui/main_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_mediaCredits);
  await S.load();
  await Backend.I.init();
  await Notifications.I.init();
  await AppState.I.load();
  if (Backend.I.user != null) await AppState.I.syncFromCloud();
  await AppState.I.rescheduleReminders();
  runApp(const SleepApp());
}

/// First-run journey, as in the original: onboarding → account → free-trial
/// explainer → five-tab app. Later launches go straight to the tabs.
class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the theme preference changes, not on every state tick.
    return ValueListenableBuilder<String>(
      valueListenable: AppState.I.themeName,
      builder: (context, name, _) => MaterialApp(
        title: 'Sleep Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(AppThemeId.byLabel(name).palette),
        home: _home,
      ),
    );
  }

  Widget get _home => AppState.I.onboarded
      ? const MainShell()
      : Builder(
          builder: (context) => OnboardingScreen(
            onDone: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WelcomeScreen())),
          ),
        );
}

/// Credits for the bundled recordings, stories and photos (several are
/// CC BY / CC BY-SA and need attribution), shown with the software licences.
Stream<LicenseEntry> _mediaCredits() async* {
  for (final f in ['assets/free/CREDITS.md', 'assets/free/CREDITS-audio.md']) {
    try {
      yield LicenseEntryWithLineBreaks(['Sounds, music, stories and photos'], await rootBundle.loadString(f));
    } catch (_) {}
  }
}
