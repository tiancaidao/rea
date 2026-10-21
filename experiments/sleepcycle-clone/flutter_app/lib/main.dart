import 'package:flutter/material.dart';
import 'theme.dart';
import 'data/models.dart';
import 'data/api_client.dart';
import 'ui/sleep_session_screen.dart';
import 'ui/results_screen.dart';
import 'ui/alarm_settings_screen.dart';
import 'ui/login_screen.dart';
import 'ui/sleep_aid_screen.dart';
import 'ui/paywall_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/stats_screen.dart';

void main() => runApp(const SleepApp());

class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AlarmSettings settings = AlarmSettings(alarmTime: const TimeOfDayLike(7, 30));
  final SleepApi api = SleepApi();

  @override
  void initState() {
    super.initState();
    // First run: show the onboarding flow once. (Persist a flag with
    // shared_preferences in a real build; shown every launch here for demo.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    });
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Sign in',
            icon: const Icon(Icons.person_outline),
            onPressed: () => _open(LoginScreen(api: api)),
          ),
          IconButton(
            tooltip: 'Sleep aid',
            icon: const Icon(Icons.music_note_outlined),
            onPressed: () => _open(SleepAidScreen(api: api)),
          ),
          IconButton(
            tooltip: 'Premium',
            icon: const Icon(Icons.workspace_premium_outlined),
            onPressed: () => _open(PaywallScreen(api: api)),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text('Good night', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Smart alarm at ${settings.alarmTime} '
                  '(±${settings.windowMinutes} min)',
                  style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              const Icon(Icons.nightlight_round, size: 96, color: Color(0xFF6C7BFF)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SleepSessionScreen(settings: settings),
                  ),
                ),
                icon: const Icon(Icons.bedtime),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Start sleep tracking'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final updated = await Navigator.push<AlarmSettings>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlarmSettingsScreen(settings: settings),
                    ),
                  );
                  if (updated != null) setState(() => settings = updated);
                },
                icon: const Icon(Icons.alarm),
                label: const Text('Alarm settings'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _open(const ResultsDemoLoader()),
                    child: const Text('Sample night'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _open(const StatsScreen()),
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: const Text('Trends'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
