import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../alarm/custom_song.dart';
import '../app_state.dart';
import '../backend/backend.dart';
import '../device/health_connect.dart';
import '../device/location.dart';
import '../device/notifications.dart';
import '../device/wear.dart';
import '../theme.dart';
import '../paywall/paywall_config.dart';
import '../paywall/paywall_screen.dart';
import 'sleep_aid_sheet.dart' show PremiumBadge;
import 'welcome_screen.dart' show WelcomeScreen;
import 'widgets/common.dart';
import 'widgets/illustrations.dart';

/// Every settings screen reachable from Profile and Profile › More. They all
/// share one template (SettingsPage + PrefRadioList + AboutBlock). Copy is our
/// own; behaviour is local to the prototype's AppState.

// ── Profile › Settings ──────────────────────────────────────────────────────

// ── Theme ───────────────────────────────────────────────────────────────────

/// Picks the app theme. Each option previews its own palette (backdrop, card
/// and the four stage colors) so the choice is visible before it is applied.
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Watch((context, s) => SettingsPage(title: 'Theme', children: [
          const SizedBox(height: 8),
          for (final t in AppThemeId.values)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _ThemeOption(
                theme: t,
                selected: AppThemeId.byLabel(s.pref('theme')) == t,
                onTap: () => s.setPref('theme', t.label),
              ),
            ),
          const AboutBlock('Midnight and Mist share the same layouts and differ only in palette: '
              'dark glass with a blue stage gradient for the bedroom, and a misty light theme for daytime. '
              'Classic keeps the original teal look.'),
        ]));
  }
}

class _ThemeOption extends StatelessWidget {
  final AppThemeId theme;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({required this.theme, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cur = context.palette;
    final t = theme.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cur.surface,
          borderRadius: BorderRadius.circular(cur.radius),
          border: Border.all(color: selected ? cur.accent : cur.stroke, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          // miniature of the theme: its sky, a card and the stage colors
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: t.backdrop),
              border: Border.all(color: cur.stroke),
            ),
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.stroke),
              ),
              padding: const EdgeInsets.all(6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (c, h) in [(t.deep, 0.9), (t.light, 0.6), (t.rem, 0.75), (t.awake, 0.3)])
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: h,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(theme.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(theme.blurb, style: TextStyle(color: cur.textMuted, height: 1.3)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: cur.accent),
        ]),
      ),
    );
  }
}

class SleepGoalPage extends StatelessWidget {
  const SleepGoalPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'Sleep Goal', children: [
      const SizedBox(height: 40),
      const Center(child: CircleArt(icon: Icons.track_changes, art: Art.sleepGoal, size: 240)),
      const AboutBlock(
          'Going to bed and getting up at the same times every day is one of the most effective ways to sleep better. '
          'Set a goal and we\'ll track how often you hit it.'),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Watch((context, s) => PillButton(
              s.pref('sleep_goal') == 'Not set' ? 'Create a Sleep Goal' : 'Change Sleep Goal',
              onPressed: () async {
                final h = await showModalBottomSheet<String>(
                  context: context,
                  builder: (c) => ListView(shrinkWrap: true, children: [
                    for (final g in ['6h 30m', '7h', '7h 30m', '8h', '8h 30m', '9h'])
                      ListTile(title: Text(g), onTap: () => Navigator.pop(c, g)),
                  ]),
                );
                if (h != null) s.setPref('sleep_goal', h);
              },
            )),
      ),
    ]);
  }
}

class AlarmSoundPage extends StatelessWidget {
  const AlarmSoundPage({super.key});
  static const free = [
    'Soft breeze',
    'Forest clearing',
    'Morning haze',
    'First light',
    'Dewdrops',
    'Classical morning',
    'Rain and wind',
    'Far memories',
  ];
  static const premium = [
    'Slow waltz',
    'Songbird',
    'City dawn',
    'Meadow',
    'Sea dreams',
    'Riddle',
    'Stillness',
    'Winter moon',
    'Park bench',
    'Metro',
    'Good morning',
  ];

  /// Local file for an alarm sound name: a stable pick from the alarm sounds
  /// extracted into assets/audio/ (comparison placeholders), if present.
  static String? fileFor(String name) {
    final pool = AppState.I.alarmAudio;
    final all = [...free, ...premium];
    if (pool.isEmpty) return AppState.ownAlarmFor(name, all);
    return pool[math.max(0, all.indexOf(name)) % pool.length];
  }

  static Future<void> _preview(String name) async {
    final f = fileFor(name);
    if (f == null) return;
    final p = AppState.I.player;
    try {
      await p.setAsset(f);
      await p.play();
      await Future.delayed(const Duration(seconds: 4));
      await p.stop();
    } catch (_) {
      // no local placeholder audio: selection still works, just silent
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'Sound', children: [
      const PrefRadioList(prefKey: 'alarm_sound', options: free, onPicked: _preview),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text('Premium sounds', style: TextStyle(color: context.palette.textMuted)),
      ),
      const PrefRadioList(prefKey: 'alarm_sound', options: premium, onPicked: _preview),
      Watch((context, s) {
        final picked = s.pref('alarm_sound') == CustomSong.label && CustomSong.path != null;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(picked ? Icons.radio_button_checked : Icons.library_music, color: context.palette.accent),
          title: const Text(CustomSong.label, style: TextStyle(fontSize: 16)),
          subtitle: Text(CustomSong.path == null ? 'Pick any song on your phone' : CustomSong.title,
              style: TextStyle(color: context.palette.textMuted)),
          trailing: s.premium ? null : const PremiumBadge(),
          onTap: () async {
            if (!s.premium) {
              showPaywall(context, Placement.lockedFeature);
              return;
            }
            if (CustomSong.path != null && !picked) {
              s.setPref('alarm_sound', CustomSong.label);
              return;
            }
            try {
              await CustomSong.pick();
            } catch (_) {
              if (context.mounted) toast(context, 'Couldn\'t open that file. Try another song.');
            }
          },
        );
      }),
      const AboutBlock('Premium lets you wake up to any song on your phone. It plays at alarm volume and fades in '
          'like the built-in sounds.'),
    ]);
  }
}

class WakeUpPhasePage extends StatelessWidget {
  const WakeUpPhasePage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Wake up phase', children: [
        _Radio('wake_phase', ['10', '15', '20', '30'], suffix: ' minutes'),
        AboutBlock('The smart alarm wakes you at your lightest moment within this window, ending at your alarm time. '
            'A 30-minute window gives the best chance of catching light sleep.'),
      ]);
}

class WeeklyReportPage extends StatelessWidget {
  const WeeklyReportPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Weekly report', children: [
        PrefRadioList(header: 'Weekly report', prefKey: 'weekly_report', options: ['On', 'Off']),
        PrefRadioList(
            header: 'Notify me when my report is ready', prefKey: 'weekly_report_notify', options: ['On', 'Off']),
        AboutBlock(
            'A short summary of your week, found in the Journal next to the days at the top. '
            'It needs at least four tracked nights in the week.',
            art: CircleArt(icon: Icons.description, art: Art.weeklyReport)),
      ]);
}

class BedtimeReminderPage extends StatelessWidget {
  const BedtimeReminderPage({super.key});
  static const options = [
    'No reminder',
    'At bedtime',
    '15 minutes before',
    '30 minutes before',
    '45 minutes before',
    '60 minutes before',
  ];
  @override
  Widget build(BuildContext context) => Watch((context, s) => SettingsPage(title: 'Bedtime reminder', children: [
        PrefRadioList(
            prefKey: 'bedtime_reminder',
            options: options,
            onPicked: (o) {
              if (o != 'No reminder') Notifications.I.requestPermission();
            }),
        AboutBlock(
            'Your bedtime is ${fmtDt(s.bedtime)}: your alarm time minus your sleep goal'
            '${s.pref('sleep_goal') == 'Not set' ? ' (8 hours until you set one)' : ''}. '
            'We\'ll remind you to start tracking and put your phone by your bed.',
            art: const CircleArt(icon: Icons.bedtime, art: Art.alarm)),
      ]));
}

// ── Profile › More ──────────────────────────────────────────────────────────

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Watch((context, s) {
      void open(Widget w) => push(context, w);
      return SettingsPage(title: 'More', children: [
        const SectionTitle('Personal'),
        NavRow(icon: Icons.person, title: 'Account', onTap: () => open(const AccountPage())),
        NavRow(icon: Icons.straighten, title: 'About you', onTap: () => open(const AboutYouPage())),
        NavRow(icon: Icons.thumb_up, title: 'Consent and privacy', onTap: () => open(const ConsentPage())),
        NavRow(
            icon: Icons.favorite,
            title: 'Health Connect',
            value: s.pref('health_connect') == 'On' ? 'Connected' : 'Not connected',
            onTap: () => open(const HealthConnectPage())),
        const SectionTitle('Alarm'),
        NavRow(
            icon: Icons.sensors,
            title: 'Motion detection',
            value: s.pref('motion_detection').split(' ').first,
            onTap: () => open(const SimpleRadioPage(
                'Motion detection', 'motion_detection', ['Microphone (recommended)', 'Accelerometer'],
                about:
                    'The microphone works with the phone on the nightstand. With the accelerometer, the phone must lie on the mattress.',
                art: Icons.phone_android,
                illustration: Art.motion))),
        NavRow(
            icon: Icons.mic,
            title: 'Sound detection',
            value: s.pref('sound_detection').split(' (').first,
            onTap: () => open(const SimpleRadioPage('Sound detection', 'sound_detection',
                ['0 nights', '1 night', '20 nights (recommended)', '100 nights', 'Forever'],
                header: 'Keep audio clips for',
                about: 'Short clips of snoring and talking are kept on your phone for this long.'))),
        NavRow(
            icon: Icons.info,
            title: 'Placement reminders',
            value: s.pref('placement_reminders'),
            onTap: () => open(const SimpleRadioPage('Placement reminders', 'placement_reminders', ['On', 'Off'],
                about: 'Show the placement and snooze tips each time you start tracking.'))),
        NavRow(
            icon: Icons.snooze,
            title: 'Snooze',
            value: s.pref('snooze').split(' (').first,
            onTap: () => open(const SimpleRadioPage('Snooze', 'snooze', ['Smart (recommended)', 'Regular', 'Off'],
                about: 'Smart snooze shortens each snooze as your alarm time gets closer, so you still get up on time.',
                art: Icons.touch_app,
                illustration: Art.snooze))),
        NavRow(
            icon: Icons.vibration,
            title: 'Vibration',
            value: s.pref('vibration'),
            onTap: () => open(const SimpleRadioPage('Vibration', 'vibration', ['As backup', 'Never', 'Only vibration'],
                about: 'As backup, vibration starts if the alarm sound alone hasn\'t woken you.'))),
        NavRow(
            icon: Icons.battery_alert,
            title: 'Battery warning',
            value: s.pref('battery_warning'),
            onTap: () => open(const SimpleRadioPage('Battery warning', 'battery_warning', ['On', 'Off'],
                about: 'Sound the alarm early if the battery is about to run out during the night.'))),
        const SectionTitle('Other'),
        NavRow(icon: Icons.storage, title: 'Database', onTap: () => open(const DatabasePage())),
        NavRow(
            icon: Icons.extension,
            title: 'Third-party software and media',
            onTap: () => showLicensePage(context: context, applicationName: 'Lullwake')),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text('Lullwake v0.1.0', style: TextStyle(color: context.palette.textFaint))),
        ),
      ]);
    });
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    Widget link(String t, VoidCallback onTap, {Color? color}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t, style: TextStyle(color: color ?? context.palette.accent, fontSize: 16)),
          ),
        );
    return SettingsPage(title: 'Account', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Email: ${s.email}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          link('Manage account', () async {
            final u = Backend.I.user;
            if (u == null) return toast(context, 'Sign in to manage your account');
            await Backend.I.sendPasswordReset();
            if (context.mounted) toast(context, 'Password reset email sent to ${u.email}');
          }),
          link('Log out', () async {
            if (await confirm(context, 'Log out?', 'Your nights stay backed up online.', 'Log out')) {
              s.logOut();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
            }
          }),
          link('Erase your data', () async {
            if (await confirm(context, 'Erase your data?', 'All nights will be deleted.', 'Erase')) s.eraseAll();
          }, color: context.palette.awake),
          link('Erase your data and account', () async {
            if (await confirm(context, 'Erase data and account?', 'This cannot be undone.', 'Erase')) {
              try {
                await Backend.I.deleteAccount();
              } catch (e) {
                if (context.mounted) toast(context, 'Couldn\'t delete the account: $e');
                return;
              }
              s.nights.clear();
              s.logOut();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
            }
          }, color: context.palette.awake),
        ]),
      ),
      const AboutBlock('Manage your sign-in details and your data.'),
    ]);
  }
}

class AboutYouPage extends StatelessWidget {
  const AboutYouPage({super.key});
  @override
  Widget build(BuildContext context) => Watch((context, s) {
        void open(String t, String k, List<String> o) => push(context, SimpleRadioPage(t, k, o));
        return SettingsPage(title: 'About you', children: [
          NavRow(
              title: 'Unit of measurement',
              value: s.pref('units'),
              onTap: () => open('Unit of measurement', 'units', ['Metric', 'Imperial'])),
          NavRow(
              title: 'Weight',
              value: s.pref('weight'),
              onTap: () => open('Weight', 'weight', ['< 50 kg', '50–70 kg', '70–90 kg', '> 90 kg'])),
          NavRow(
              title: 'Height',
              value: s.pref('height'),
              onTap: () => open('Height', 'height', ['< 160 cm', '160–175 cm', '175–190 cm', '> 190 cm'])),
          NavRow(
              title: 'Gender',
              value: s.pref('gender'),
              onTap: () => open('Gender', 'gender', ['Female', 'Male', 'Other', 'Prefer not to say'])),
          NavRow(
              title: 'Year of birth',
              value: s.pref('birth'),
              onTap: () => open('Year of birth', 'birth', ['1960s', '1970s', '1980s', '1990s', '2000s'])),
          const PrefRadioList(
              header: 'Take part in our anonymous sleep research survey?', prefKey: 'survey', options: ['Yes', 'No']),
          const AboutBlock('These details make your analysis more accurate. Research answers are anonymous.'),
        ]);
      });
}

class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key});
  @override
  Widget build(BuildContext context) => Watch((context, s) {
        Widget block(String title, String body, String key) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(body, style: TextStyle(color: context.palette.textMuted, height: 1.4)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: s.pref(key) == 'true',
                  activeColor: context.palette.accent,
                  title: const Text('I agree'),
                  onChanged: (v) => s.setPref(key, '${v ?? false}'),
                ),
                const Divider(),
              ]),
            );
        return SettingsPage(title: 'Consent and privacy', children: [
          block('Store sleep data online', 'Needed for online backup and moving to a new phone.', 'consent_storage'),
          block('Share sounds', 'Let us use anonymous sound clips to improve snore and sound detection.',
              'consent_sounds'),
          block('Improve the product', 'Share anonymous usage statistics so we can see which features help.',
              'consent_product'),
        ]);
      });
}

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return SettingsPage(title: 'Database', children: [
      NavRow(
          icon: Icons.share,
          title: 'Export database to CSV',
          onTap: () async {
            final rows = ['start,end,quality,asleep_min,in_bed_min,snore_min,steps'];
            for (final n in s.nights) {
              rows.add('${n.wentToBed.toIso8601String()},${n.wokeUp.toIso8601String()},${n.quality},'
                  '${n.asleepMinutes},${n.inBedMinutes},${n.snoreMinutes},${n.steps ?? ''}');
            }
            try {
              final f = File('${Directory.systemTemp.path}/sleep_export.csv')..writeAsStringSync(rows.join('\n'));
              if (context.mounted) toast(context, 'Exported ${s.nights.length} nights to ${f.path}');
            } catch (_) {
              if (context.mounted) toast(context, 'Export failed');
            }
          }),
      // Full nights incl. the 30-s hypnogram, for comparison/benchmark/benchmark_night.py
      NavRow(
          icon: Icons.compare_arrows,
          title: 'Export nights for benchmarking (JSON)',
          onTap: () async {
            try {
              final f = File('${Directory.systemTemp.path}/sleep_export.json')
                ..writeAsStringSync(jsonEncode([for (final n in s.nights) n.toJson()]));
              if (context.mounted) toast(context, 'Exported ${s.nights.length} nights to ${f.path}');
            } catch (_) {
              if (context.mounted) toast(context, 'Export failed');
            }
          }),
      // Like the original's debug "Trigger alarm after 10s".
      NavRow(
          icon: Icons.alarm_on,
          title: 'Test alarm (rings 10 s after you start)',
          onTap: () {
            s.testAlarmArmed = true;
            toast(context, 'Start tracking on the Sleep tab: the alarm rings after 10 seconds');
          }),
      NavRow(icon: Icons.storefront, title: 'Preview paywalls', onTap: () => push(context, const PaywallPreviewPage())),
      // Prototype helper: populate every screen without tracking for real.
      NavRow(
          icon: Icons.science,
          title: 'Load sample nights (prototype)',
          onTap: () {
            s.loadSampleNights();
            toast(context, 'Added 7 sample nights');
          }),
      const AboutBlock('Export all your nights as a CSV file to open in a spreadsheet.'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () async {
              if (await confirm(context, 'Erase database?', 'All nights will be deleted.', 'Erase')) s.eraseAll();
            },
            child: Text('Erase database', style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
          ),
        ),
      ),
    ]);
  }
}

class HealthConnectPage extends StatelessWidget {
  const HealthConnectPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsPage(title: 'Health Connect', children: [
        PrefRadioList(
          prefKey: 'health_connect',
          options: const ['On', 'Off'],
          onPicked: (v) async {
            if (v != 'On') return;
            final ok = await HealthConnect.I.connect();
            if (!ok) {
              AppState.I.setPref('health_connect', 'Off');
              if (context.mounted) toast(context, 'Health Connect isn\'t available or permission was declined');
            }
          },
        ),
        Watch((context, s) => s.pref('health_connect') != 'On'
            ? const SizedBox.shrink()
            : ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import sleep from Health Connect'),
                subtitle: const Text('Nights from the last 30 days that other apps recorded'),
                onTap: () async {
                  final n = await AppState.I.importHealthNights();
                  if (context.mounted) {
                    toast(context, n == 0 ? 'No new nights to import' : 'Imported $n night${n == 1 ? '' : 's'}');
                  }
                },
              )),
        const AboutBlock('Read your daily steps from Health Connect and write each night back as a sleep '
            'session so other health apps can use it. You can also import nights another app or a watch '
            'recorded.'),
      ]);
}

/// Wear OS: the watch is a remote for the phone (start and stop, snooze,
/// silent wake-up by vibration) plus Snore Alert.
class WatchPage extends StatelessWidget {
  const WatchPage({super.key});
  @override
  Widget build(BuildContext context) {
    Wear.I.refresh();
    return SettingsPage(title: 'Watch', children: [
      ValueListenableBuilder(
        valueListenable: Wear.I.connected,
        builder: (context, on, _) => ListTile(
          leading: Icon(on ? Icons.watch : Icons.watch_off_outlined, color: context.palette.accent),
          title: Text(on ? 'Watch connected' : 'No watch connected'),
          subtitle: Text(on ? 'Start, stop and snooze from your wrist' : 'Install the app on your Wear OS watch',
              style: TextStyle(color: context.palette.textMuted)),
        ),
      ),
      Watch((context, s) => NavRow(
          icon: Icons.vibration,
          title: 'Alarm type',
          value: s.pref('wear_alarm_type'),
          onTap: () => push(
              context,
              const SimpleRadioPage('Alarm type', 'wear_alarm_type', ['Automatic', 'Melody', 'Vibrate'],
                  about: 'Automatic picks by where you start the night. Started from the phone: melody. '
                      'Started from the watch: the watch vibrates silently, and the phone joins in if you '
                      'are still asleep after two minutes. You can also change it on the watch.')))),
      Watch((context, s) => NavRow(
          icon: Icons.record_voice_over,
          title: 'Snore Alert',
          value: s.pref('snore_alert'),
          onTap: () => push(context, const SnoreAlertPage()))),
      const AboutBlock('Keep the phone by your bed: it does the tracking and decides when to wake you. '
          'Think of the watch as a remote that can wake you silently.'),
    ]);
  }
}

/// Snore Alert: an intro (three pages), consent, then the switch. While
/// tracking, ongoing snoring buzzes the watch to nudge you onto your side.
class SnoreAlertPage extends StatefulWidget {
  const SnoreAlertPage({super.key});
  @override
  State<SnoreAlertPage> createState() => _SnoreAlertPageState();
}

class _SnoreAlertPageState extends State<SnoreAlertPage> {
  int _page = 0;
  static const _intro = [
    (
      Icons.watch,
      'Snore Alert',
      'When the phone hears you snoring, your watch vibrates gently so you change position.'
    ),
    (
      Icons.airline_seat_flat,
      'Sleep on your side',
      'Lying on your back can narrow the airway and make snoring worse. Turning to your side often helps.'
    ),
    (
      Icons.science,
      'Still experimental',
      'It only works if you are the only one snoring in the room, and the buzzing can disturb your sleep. '
          'Turn it on only if you accept that.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    if (s.pref('snore_alert') == 'On' || _page >= _intro.length) {
      return SettingsPage(title: 'Snore Alert', children: [
        PrefRadioList(prefKey: 'snore_alert', options: const ['On', 'Off']),
        AboutBlock(Wear.I.connected.value
            ? 'Buzzes at most every 10 minutes while snoring goes on.'
            : 'Connect a Wear OS watch with the app for Snore Alert to work.'),
      ]);
    }
    final (icon, title, body) = _intro[_page];
    final last = _page == _intro.length - 1;
    return SettingsPage(title: 'Snore Alert', children: [
      const SizedBox(height: 32),
      Center(child: CircleArt(icon: icon, size: 180)),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
        child:
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(body, textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, height: 1.4)),
      ),
      const SizedBox(height: 32),
      Center(
        child: PillButton(last ? 'I understand, turn it on' : 'Next', width: 260, onPressed: () {
          if (last) s.setPref('snore_alert', 'On');
          setState(() => _page++);
        }),
      ),
    ]);
  }
}

// ── Profile › Premium ───────────────────────────────────────────────────────

class OnlineBackupPage extends StatelessWidget {
  const OnlineBackupPage({super.key});
  @override
  Widget build(BuildContext context) => const SimpleRadioPage('Online backup', 'online_backup', ['On', 'Off'],
      about: 'Keep your nights safe online so nothing is lost if you change or lose your phone.');
}

class SleepAidSettingsPage extends StatelessWidget {
  const SleepAidSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Sleep aid', children: [
        PrefRadioList(header: 'Download files', prefKey: 'sleep_aid_download', options: ['Always', 'Wi-Fi only']),
        PrefRadioList(
            header: 'Keep downloaded files for',
            prefKey: 'sleep_aid_keep',
            options: ['1 night', '20 nights (recommended)', 'Forever']),
        PrefRadioList(header: 'Fade out ambient sounds after', prefKey: 'sleep_aid_fade', options: [
          'Smart (recommended)',
          '10 minutes',
          '20 minutes',
          '30 minutes',
          '45 minutes',
          '60 minutes',
          '90 minutes',
          'All night'
        ]),
      ]);
}

class SleepNotesPage extends StatelessWidget {
  const SleepNotesPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsPage(title: 'Sleep notes', children: [
        const _Radio('sleep_notes', ['Show', 'Hide']),
        const Divider(indent: 20, endIndent: 20),
        NavRow(title: 'Edit sleep notes', onTap: () => push(context, const EditSleepNotesPage())),
        Watch((context, s) => NavRow(
            title: 'Home location',
            value: s.pref('home_location').isEmpty ? 'Not set' : 'Set',
            onTap: () async {
              final loc = await coarseLocation();
              if (!context.mounted) return;
              if (loc == null) {
                toast(context, 'Location is off. Allow it to tag nights away from home.');
                return;
              }
              s.setPref('home_location', '${loc.$1},${loc.$2}');
              toast(context, 'Home set. Nights far from here get the Travel note.');
            })),
        const AboutBlock('Tag each night with things that might affect your sleep — then see which ones matter.'),
      ]);
}

class EditSleepNotesPage extends StatelessWidget {
  const EditSleepNotesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.palette.accent), onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('Sleep notes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Watch((context, _) => ReorderableListView(
            onReorder: (a, b) {
              final it = s.sleepNotes.removeAt(a);
              s.sleepNotes.insert(b > a ? b - 1 : b, it);
              s.notesChanged();
            },
            footer: ListTile(
              leading: Icon(Icons.add_circle, color: context.palette.positive),
              title: const Text('Add new…'),
              onTap: () async {
                final c = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('New sleep note'),
                    content: TextField(controller: c, autofocus: true),
                    actions: [TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Add'))],
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  s.sleepNotes.add(name);
                  s.notesChanged();
                }
              },
            ),
            children: [
              for (final n in s.sleepNotes)
                ListTile(
                  key: ValueKey(n),
                  leading: IconButton(
                    icon: Icon(Icons.remove_circle, color: context.palette.awake),
                    onPressed: () {
                      s.sleepNotes.remove(n);
                      s.notesChanged();
                    },
                  ),
                  title: Text(n),
                  trailing: Icon(Icons.drag_handle, color: context.palette.accent),
                ),
            ],
          )),
    );
  }
}

class WakeUpMoodPage extends StatelessWidget {
  const WakeUpMoodPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Wake up mood', children: [
        _Radio('wake_up_mood', ['Show', 'Hide']),
        AboutBlock('Log how you feel when you wake, and compare it with what the numbers say.',
            art: Text('☹️  😐  🙂', style: TextStyle(fontSize: 36))),
      ]);
}

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Weather', children: [
        _Radio('weather', ['Show', 'Hide']),
        AboutBlock('Show the morning weather when you wake up. Uses your approximate location.'),
      ]);
}

class WhosSnoringPage extends StatelessWidget {
  const WhosSnoringPage({super.key});
  @override
  Widget build(BuildContext context) => const SimpleRadioPage("Who's snoring", 'whos_snoring', ['On', 'Off'],
      about: 'Tell your snoring apart from a partner\'s. Confirm a few clips and detection learns your voice.',
      art: Icons.record_voice_over,
      artAsset: 'assets/images/who_is_snoring_fallback.jpg');
}

// ── Gift / Help ─────────────────────────────────────────────────────────────

class BenefitsPage extends StatelessWidget {
  const BenefitsPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsPage(title: 'Benefits', children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 40, 32, 40),
          child: Text('Offers and gifts for you and your friends will show up here.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        const Center(child: CircleArt(icon: Icons.card_giftcard, art: Art.gift, size: 220)),
        const SizedBox(height: 32),
        Center(
          child: PillButton('Redeem a gift card', width: 240, onPressed: () => redeemGiftCard(context)),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => showPaywall(context, Placement.giftCards),
            child: Text('Give Premium to two friends', style: TextStyle(color: context.palette.accent)),
          ),
        ),
      ]);
}

/// Every paywall variant the server can send, to open one directly
/// (Profile › More › Database). The live choice per placement is the
/// server's; this skips the experiment.
class PaywallPreviewPage extends StatelessWidget {
  const PaywallPreviewPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsPage(title: 'Preview paywalls', children: [
        FutureBuilder(
          future: Paywalls.I.variants(),
          builder: (context, snap) => Column(children: [
            for (final (id, name) in snap.data ?? const <(String, String)>[])
              NavRow(title: name, value: id, onTap: () => showPaywall(context, Placement.inApp, variant: id)),
          ]),
        ),
        const AboutBlock('Which paywall a person sees is decided by the server for each placement '
            '(onboarding, in-app, locked feature, gift cards, campaign, app open), as a sticky A/B split. '
            'Change the split or the copy in Firestore at config/paywalls without a release.'),
      ]);
}

/// Enter a gift-card code; the backend checks it and grants Premium.
Future<void> redeemGiftCard(BuildContext context) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Redeem gift card'),
      content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Redeem')),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;
  if (Backend.I.user == null) {
    toast(context, 'Sign in first to redeem a gift card');
    return;
  }
  try {
    final r = await Backend.I.redeemGiftCard(code);
    AppState.I.premium = true;
    AppState.I.notesChanged();
    if (context.mounted) toast(context, 'Premium unlocked until ${r?['premiumUntil'] ?? 'later'}');
  } catch (e) {
    if (context.mounted) toast(context, 'That code didn\'t work: $e');
  }
}

/// Help center: topics with their articles, a search across every question
/// and answer, and Contact support (an email with the app and device details
/// filled in).
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});
  static const topics = {
    'Getting started': [
      (
        'Where should I put my phone?',
        'Next to your bed, screen down and charging, when tracking with the microphone. With the '
            'accelerometer, put it on the mattress near your pillow.'
      ),
      (
        'Do I need to be online?',
        'No. Tracking and analysis run on your phone. Weather, backup and streamed '
            'sleep aid need a connection.'
      ),
      (
        'Can two people sleep in the same bed?',
        'Yes. With the microphone, keep the phone on your side of the '
            'bed; sounds closest to the phone count most.'
      ),
      (
        'How do I start without an alarm?',
        'Pick "No alarm" under the alarm time, or long-press the app icon and '
            'choose Start without alarm.'
      ),
    ],
    'Top questions': [
      (
        'Why did the alarm ring before my alarm time?',
        'The smart alarm wakes you in light sleep within your wake-up phase (30 minutes by default). Set the '
            'phase in Profile › Settings › Wake up phase, or use a regular alarm.'
      ),
      (
        'How is quality calculated?',
        'From time asleep, how often you woke, and how much deep and REM sleep you '
            'had, compared with what is typical for you.'
      ),
      (
        'Why is my graph flat?',
        'The phone didn\'t pick up movement or sound. Check its placement and that the '
            'microphone permission is on.'
      ),
      (
        'Why did the alarm not ring?',
        'Keep the app open while tracking and allow Alarms & reminders. Battery '
            'savers can stop apps overnight; exclude this app in your phone\'s battery settings.'
      ),
      (
        'What do the snore minutes mean?',
        'Minutes of the night with sounds classified as snoring. Turn on Sound '
            'detection to keep the recordings so you can listen back.'
      ),
    ],
    'Sleep aid': [
      (
        'Can I listen offline?',
        'Free sounds are part of the app. Streamed tracks download when you open them; '
            'set Wi-Fi only and how long to keep them in Profile › Settings › Sleep aid.'
      ),
      (
        'How do I stop the sound?',
        'It fades out after the time you set. You can also pause or stop it from the '
            'notification.'
      ),
    ],
    'Subscriptions': [
      (
        'How do I cancel my trial?',
        'In your phone\'s app store subscriptions, before the trial ends. Deleting '
            'the app doesn\'t cancel it.'
      ),
      (
        'I paid but Premium is locked',
        'Profile › Premium › Restore purchases, signed in with the same store '
            'account.'
      ),
      ('How do I redeem a gift card?', 'Profile › Premium › Redeem gift code.'),
    ],
    'Account settings': [
      ('How do I export my data?', 'Profile › More › Database › Export database to CSV.'),
      (
        'How do I move to a new phone?',
        'Turn on Online backup and sign in on the new phone with the same '
            'account.'
      ),
      (
        'How do I delete my data?',
        'Profile › More › Database › Erase all data. Signed in, this also erases the '
            'online copy.'
      ),
      ('Can I import nights from my watch?', 'Turn on Health Connect and tap Import sleep from Health Connect.'),
    ],
  };

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _q = '';

  Widget _article(BuildContext context, (String, String) qa) => ExpansionTile(title: Text(qa.$1), children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(qa.$2)),
      ]);

  Future<void> _contact() async {
    final info = 'App: Lullwake\nPlatform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'Nights: ${AppState.I.nights.length}\n\nDescribe the problem:\n';
    final uri = Uri(
        scheme: 'mailto',
        query: 'subject=${Uri.encodeComponent('Help with Lullwake')}'
            '&body=${Uri.encodeComponent(info)}');
    if (!await launchUrl(uri) && mounted) toast(context, 'No email app found');
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final hits = [
      for (final t in HelpPage.topics.values)
        for (final qa in t)
          if (q.isNotEmpty && (qa.$1.toLowerCase().contains(q) || qa.$2.toLowerCase().contains(q))) qa,
    ];
    return SettingsPage(title: 'Help', children: [
      Container(
        color: context.palette.surfaceHi,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(children: [
          const Text('Help center', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Search',
              hintStyle: TextStyle(color: Colors.black45),
              prefixIcon: Icon(Icons.search, color: Colors.black45),
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
            ),
            style: const TextStyle(color: Colors.black),
          ),
        ]),
      ),
      if (q.isNotEmpty) ...[
        if (hits.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No articles match "$_q".', style: TextStyle(color: context.palette.textMuted)),
          ),
        for (final qa in hits) _article(context, qa),
      ] else
        for (final t in HelpPage.topics.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  side: BorderSide(color: context.palette.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
              onPressed: () => push(
                  context, SettingsPage(title: t.key, children: [for (final qa in t.value) _article(context, qa)])),
              child: Text(t.key, style: TextStyle(color: context.palette.accent, fontSize: 16)),
            ),
          ),
      const SizedBox(height: 24),
      NavRow(icon: Icons.mail_outline, title: 'Contact support', onTap: _contact),
    ]);
  }
}

// ── helpers ─────────────────────────────────────────────────────────────────

/// Radio list + About + optional illustration on one page.
class SimpleRadioPage extends StatelessWidget {
  final String title;
  final String prefKey;
  final List<String> options;
  final String? about;
  final String? header;
  final IconData? art;
  final String? artAsset;
  final Art? illustration;
  const SimpleRadioPage(this.title, this.prefKey, this.options,
      {super.key, this.about, this.header, this.art, this.artAsset, this.illustration});
  @override
  Widget build(BuildContext context) => SettingsPage(title: title, children: [
        PrefRadioList(header: header, prefKey: prefKey, options: options),
        if (about != null)
          AboutBlock(about!, art: art == null ? null : CircleArt(asset: artAsset, icon: art!, art: illustration)),
      ]);
}

/// Radio list whose stored value is the option without a display suffix.
class _Radio extends StatelessWidget {
  final String prefKey;
  final List<String> options;
  final String suffix;
  const _Radio(this.prefKey, this.options, {this.suffix = ''});
  @override
  Widget build(BuildContext context) => Watch((context, s) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          for (final o in options)
            InkWell(
              onTap: () => s.setPref(prefKey, o),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(s.pref(prefKey) == o ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: context.palette.accent, size: 22),
                  const SizedBox(width: 16),
                  Text('$o$suffix', style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
        ]),
      ));
}
