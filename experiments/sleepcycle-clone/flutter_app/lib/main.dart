import 'package:flutter/material.dart';
import 'theme.dart';
import 'strings.dart';
import 'ui/main_shell.dart';
import 'ui/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await S.load();
  runApp(const SleepApp());
}

class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    // First run: show onboarding once. (Persist a flag with shared_preferences
    // in a real build; shown every launch here for the demo.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    });
  }

  @override
  Widget build(BuildContext context) => const MainShell();
}
