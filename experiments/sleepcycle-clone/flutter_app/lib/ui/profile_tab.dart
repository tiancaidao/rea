import 'package:flutter/material.dart';
import '../theme.dart';
import 'settings_pages.dart';
import 'widgets/common.dart';

/// Profile tab: summary tiles, then Settings, Premium and Help groups — each
/// row opens a settings page built from the shared radio + About template.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Watch((context, s) {
          final n = s.nights;
          final avgQ = n.isEmpty ? '—' : '${n.map((e) => e.quality).reduce((a, b) => a + b) ~/ n.length}%';
          final avgT = n.isEmpty
              ? '—'
              : fmtDuration(n.map((e) => e.asleepMinutes).reduce((a, b) => a + b) ~/ n.length);
          void open(Widget w) => push(context, w);
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 8, 8),
              child: Row(children: [
                const Text('Profile', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.card_giftcard, color: AppTheme.accent),
                  onPressed: () => open(const BenefitsPage()),
                ),
              ]),
            ),
            const Divider(indent: 20, endIndent: 20, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.5,
                children: [
                  _Tile(Icons.nightlight_round, n.isEmpty ? '—' : '${n.length}', 'Nights'),
                  _Tile(Icons.donut_large, avgQ, 'Avg. quality', color: const Color(0xFFD08A2E)),
                  _Tile(Icons.schedule, avgT, 'Avg. time'),
                  _Tile(Icons.cloud_done, s.pref('online_backup') == 'On' ? 'OK' : 'Off', 'Backup',
                      color: Colors.greenAccent),
                ],
              ),
            ),
            const Divider(indent: 20, endIndent: 20, color: Colors.white12),
            const SectionTitle('Settings'),
            NavRow(icon: Icons.track_changes, title: 'Sleep Goal', value: s.pref('sleep_goal'),
                onTap: () => open(const SleepGoalPage())),
            NavRow(icon: Icons.music_note, title: 'Sound', value: s.pref('alarm_sound'),
                onTap: () => open(const AlarmSoundPage())),
            NavRow(icon: Icons.alarm, title: 'Wake up phase', value: '${s.pref('wake_phase')} min',
                onTap: () => open(const WakeUpPhasePage())),
            NavRow(icon: Icons.watch, title: 'Watch', onTap: () => open(const WatchPage())),
            NavRow(icon: Icons.description_outlined, title: 'Weekly report', value: s.pref('weekly_report'),
                onTap: () => open(const WeeklyReportPage())),
            NavRow(icon: Icons.more_horiz, title: 'More', onTap: () => open(const MorePage())),
            const SectionTitle('Premium'),
            NavRow(icon: Icons.cloud, title: 'Online backup', value: s.pref('online_backup'),
                onTap: () => open(const OnlineBackupPage())),
            NavRow(icon: Icons.bedtime, title: 'Sleep aid', onTap: () => open(const SleepAidSettingsPage())),
            NavRow(icon: Icons.edit, title: 'Sleep notes', value: _onOff(s.pref('sleep_notes')),
                onTap: () => open(const SleepNotesPage())),
            NavRow(icon: Icons.sentiment_satisfied, title: 'Wake up mood', value: _onOff(s.pref('wake_up_mood')),
                onTap: () => open(const WakeUpMoodPage())),
            NavRow(icon: Icons.cloud_queue, title: 'Weather', value: _onOff(s.pref('weather')),
                onTap: () => open(const WeatherPage())),
            NavRow(icon: Icons.record_voice_over, title: "Who's snoring", value: s.pref('whos_snoring'),
                onTap: () => open(const WhosSnoringPage())),
            const SectionTitle('Help'),
            NavRow(icon: Icons.help, title: 'Help', onTap: () => open(const HelpPage())),
          ]);
        }),
      ),
    );
  }

  static String _onOff(String showHide) => showHide == 'Show' ? 'On' : 'Off';
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _Tile(this.icon, this.value, this.label, {this.color = AppTheme.accent});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 30),
      const SizedBox(width: 12),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      ),
    ]);
  }
}
