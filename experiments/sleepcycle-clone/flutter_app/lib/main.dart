import 'package:flutter/material.dart';
import 'app_state.dart';
import 'backend/backend.dart';
import 'theme.dart';
import 'strings.dart';
import 'ui/main_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await S.load();
  await Backend.I.init();
  await AppState.I.load();
  if (Backend.I.user != null) await AppState.I.syncFromCloud();
  runApp(const SleepApp());
}

/// First-run journey, as in the original: onboarding → account → free-trial
/// explainer → five-tab app. Later launches go straight to the tabs.
class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: AppState.I.onboarded
          ? const MainShell()
          : Builder(
              builder: (context) => OnboardingScreen(
                onDone: () => Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (_) => const WelcomeScreen())),
              ),
            ),
    );
  }
}
