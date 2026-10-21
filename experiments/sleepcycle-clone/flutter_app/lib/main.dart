import 'package:flutter/material.dart';
import 'theme.dart';
import 'strings.dart';
import 'ui/onboarding_screen.dart';
import 'ui/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await S.load();
  runApp(const SleepApp());
}

/// First-run journey, as in the original: onboarding → account → free-trial
/// explainer → five-tab app. (A real build persists "onboarded"/"signed in"
/// and skips straight to the tabs on later launches.)
class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => OnboardingScreen(
          onDone: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const WelcomeScreen())),
        ),
      ),
    );
  }
}
