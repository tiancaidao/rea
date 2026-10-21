import 'package:flutter/material.dart';
import 'data/models.dart';
import 'data/api_client.dart';
import 'ui/sleep_session_screen.dart';
import 'ui/results_screen.dart';
import 'ui/alarm_settings_screen.dart';
import 'ui/login_screen.dart';
import 'ui/sleep_aid_screen.dart';
import 'ui/paywall_screen.dart';

void main() => runApp(const SleepApp());

class SleepApp extends StatelessWidget {
  const SleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C7BFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1026),
      ),
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
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ResultsDemoLoader()),
                ),
                child: const Text('See a sample night'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
