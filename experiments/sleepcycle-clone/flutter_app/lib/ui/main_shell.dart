import 'package:flutter/material.dart';
import '../theme.dart';
import '../strings.dart';
import '../data/models.dart';
import '../data/api_client.dart';
import 'sleep_session_screen.dart';
import 'results_screen.dart';
import 'alarm_settings_screen.dart';
import 'login_screen.dart';
import 'paywall_screen.dart';
import 'sleep_aid_screen.dart';
import 'stats_screen.dart';

/// Root with a four-tab bottom bar — Journal / Statistics / Sleep aid / Profile —
/// the same primary navigation the original uses.
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final SleepApi _api = SleepApi();
  AlarmSettings _settings = AlarmSettings(alarmTime: const TimeOfDayLike(7, 30));

  @override
  Widget build(BuildContext context) {
    final pages = [
      _JournalTab(
        settings: _settings,
        onSettingsChanged: (s) => setState(() => _settings = s),
      ),
      const StatsScreen(),
      const SleepAidScreen(),
      _ProfileTab(api: _api),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.nightlight_outlined),
              selectedIcon: const Icon(Icons.nightlight_round),
              label: S.get('tab_journal', 'Journal')),
          NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: S.get('tab_statistics', 'Statistics')),
          NavigationDestination(
              icon: const Icon(Icons.music_note_outlined),
              selectedIcon: const Icon(Icons.music_note),
              label: S.get('tab_sleep_aid', 'Sleep aid')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: S.get('tab_profile', 'Profile')),
        ],
      ),
    );
  }
}

class _JournalTab extends StatelessWidget {
  final AlarmSettings settings;
  final ValueChanged<AlarmSettings> onSettingsChanged;
  const _JournalTab({required this.settings, required this.onSettingsChanged});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.nightGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(S.get('good_morning', 'Good morning'),
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('${S.get('smart_alarm', 'Smart alarm')} · ${settings.alarmTime} '
                    '(±${settings.windowMinutes} min)',
                    style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                const Icon(Icons.nightlight_round, size: 96, color: AppTheme.primary),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => open(SleepSessionScreen(settings: settings)),
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
                          builder: (_) => AlarmSettingsScreen(settings: settings)),
                    );
                    if (updated != null) onSettingsChanged(updated);
                  },
                  icon: const Icon(Icons.alarm),
                  label: const Text('Alarm settings'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => open(const ResultsDemoLoader()),
                  child: const Text('See a sample night'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final SleepApi api;
  const _ProfileTab({required this.api});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(title: Text(S.get('tab_profile', 'Profile'))),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/icon/app_icon.png',
                  width: 72, height: 72,
                  errorBuilder: (_, __, ___) => const Icon(Icons.nightlight_round, size: 72)),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(S.get('app_name', 'Sleep Tracker'),
              style: Theme.of(context).textTheme.titleLarge)),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account'),
            subtitle: const Text('Sign in to sync your nights'),
            onTap: () => open(LoginScreen(api: api)),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(S.get('get_premium', 'Get Premium')),
            subtitle: Text(S.get('pw_sp_stats', 'See progress over time')),
            onTap: () => open(PaywallScreen(api: api)),
          ),
        ],
      ),
    );
  }
}
