import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'welcome_screen.dart';
import 'widgets/common.dart';

/// Every settings screen reachable from Profile and Profile › More. They all
/// share one template (SettingsPage + PrefRadioList + AboutBlock). Copy is our
/// own; behaviour is local to the prototype's AppState.

// ── Profile › Settings ──────────────────────────────────────────────────────

class SleepGoalPage extends StatelessWidget {
  const SleepGoalPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'Sleep Goal', children: [
      const SizedBox(height: 40),
      const Center(child: CircleArt(icon: Icons.track_changes, size: 240)),
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
                  backgroundColor: const Color(0xFF0E2230),
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
    'Soft breeze', 'Forest clearing', 'Morning haze', 'First light', 'Dewdrops', 'Classical morning',
    'Rain and wind', 'Far memories',
  ];
  static const premium = [
    'Slow waltz', 'Songbird', 'City dawn', 'Meadow', 'Sea dreams', 'Riddle', 'Stillness',
    'Winter moon', 'Park bench', 'Metro', 'Good morning',
  ];

  /// Local file for an alarm sound name: a stable pick from the alarm sounds
  /// extracted into assets/audio/ (comparison placeholders), if present.
  static String? fileFor(String name) {
    final pool = AppState.I.alarmAudio;
    if (pool.isEmpty) return null;
    final all = [...free, ...premium];
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
      PrefRadioList(prefKey: 'alarm_sound', options: free, onPicked: _preview),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text('Premium sounds', style: TextStyle(color: Colors.white60)),
      ),
      PrefRadioList(prefKey: 'alarm_sound', options: premium, onPicked: _preview),
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

class WatchPage extends StatelessWidget {
  const WatchPage({super.key});
  @override
  Widget build(BuildContext context) => Watch((context, s) => SettingsPage(title: 'Watch', children: [
        NavRow(icon: Icons.notifications, title: 'Alarm type', value: s.pref('watch_alarm_type'),
            onTap: () => push(context, const SimpleRadioPage('Alarm type', 'watch_alarm_type',
                ['Automatic', 'Phone only', 'Watch only']))),
        NavRow(icon: Icons.play_circle_outline, title: 'Automatic start', value: s.pref('watch_auto_start'),
            onTap: () => push(context, const SimpleRadioPage('Automatic start', 'watch_auto_start', ['On', 'Off']))),
        const AboutBlock('With a paired watch, keep your phone nearby — it still does the analysis — and use the '
            'watch to wake you silently. Automatic start begins tracking when the watch detects you\'ve fallen asleep.'),
      ]));
}

class WeeklyReportPage extends StatelessWidget {
  const WeeklyReportPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Weekly report', children: [
        PrefRadioList(header: 'Weekly report', prefKey: 'weekly_report', options: ['On', 'Off']),
        PrefRadioList(header: 'Notify me when my report is ready', prefKey: 'weekly_report_notify', options: ['On', 'Off']),
        AboutBlock('A short summary of your week, found in the Journal next to the days at the top.'),
      ]);
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
        NavRow(icon: Icons.favorite, title: 'Health Connect',
            value: s.pref('health_connect') == 'On' ? 'Connected' : 'Not connected',
            onTap: () => open(const SimpleRadioPage('Health Connect', 'health_connect', ['On', 'Off'],
                about: 'Read activity from Health Connect and write your sleep back so other health apps can use it.'))),
        const SectionTitle('Alarm'),
        NavRow(icon: Icons.sensors, title: 'Motion detection', value: s.pref('motion_detection').split(' ').first,
            onTap: () => open(const SimpleRadioPage('Motion detection', 'motion_detection',
                ['Microphone (recommended)', 'Accelerometer'],
                about: 'The microphone works with the phone on the nightstand. With the accelerometer, the phone must lie on the mattress.',
                art: Icons.phone_android, artAsset: 'assets/images/acc_placement_reminder.jpg'))),
        NavRow(icon: Icons.mic, title: 'Sound detection', value: s.pref('sound_detection').split(' (').first,
            onTap: () => open(const SimpleRadioPage('Sound detection', 'sound_detection',
                ['0 nights', '1 night', '20 nights (recommended)', '100 nights', 'Forever'],
                header: 'Keep audio clips for',
                about: 'Short clips of snoring and talking are kept on your phone for this long.'))),
        NavRow(icon: Icons.info, title: 'Placement reminders', value: s.pref('placement_reminders'),
            onTap: () => open(const SimpleRadioPage('Placement reminders', 'placement_reminders', ['On', 'Off'],
                about: 'Show the placement and snooze tips each time you start tracking.'))),
        NavRow(icon: Icons.snooze, title: 'Snooze', value: s.pref('snooze').split(' (').first,
            onTap: () => open(const SimpleRadioPage('Snooze', 'snooze', ['Smart (recommended)', 'Regular', 'Off'],
                about: 'Smart snooze shortens each snooze as your alarm time gets closer, so you still get up on time.',
                art: Icons.touch_app, artAsset: 'assets/images/acc_snooze_reminder.jpg'))),
        NavRow(icon: Icons.vibration, title: 'Vibration', value: s.pref('vibration'),
            onTap: () => open(const SimpleRadioPage('Vibration', 'vibration', ['As backup', 'Never', 'Only vibration'],
                about: 'As backup, vibration starts if the alarm sound alone hasn\'t woken you.'))),
        NavRow(icon: Icons.battery_alert, title: 'Battery warning', value: s.pref('battery_warning'),
            onTap: () => open(const SimpleRadioPage('Battery warning', 'battery_warning', ['On', 'Off'],
                about: 'Sound the alarm early if the battery is about to run out during the night.'))),
        const SectionTitle('Other'),
        NavRow(icon: Icons.storage, title: 'Database', onTap: () => open(const DatabasePage())),
        NavRow(icon: Icons.extension, title: 'Third-party software',
            onTap: () => showLicensePage(context: context, applicationName: 'Sleep Tracker')),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Sleep Tracker v0.1.0 (prototype)', style: TextStyle(color: Colors.white38))),
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
    Widget link(String t, VoidCallback onTap, {Color color = AppTheme.accent}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t, style: TextStyle(color: color, fontSize: 16)),
          ),
        );
    return SettingsPage(title: 'Account', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Email: ${s.email}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          link('Manage account', () => toast(context, 'Opens account management (backend not wired)')),
          link('Log out', () async {
            if (await confirm(context, 'Log out?', 'Your nights stay backed up online.', 'Log out')) {
              s.logOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
            }
          }),
          link('Erase your data', () async {
            if (await confirm(context, 'Erase your data?', 'All nights will be deleted.', 'Erase')) s.eraseAll();
          }, color: Colors.redAccent),
          link('Erase your data and account', () async {
            if (await confirm(context, 'Erase data and account?', 'This cannot be undone.', 'Erase')) {
              s.eraseAll();
              s.logOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()), (_) => false);
            }
          }, color: Colors.redAccent),
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
          NavRow(title: 'Unit of measurement', value: s.pref('units'),
              onTap: () => open('Unit of measurement', 'units', ['Metric', 'Imperial'])),
          NavRow(title: 'Weight', value: s.pref('weight'),
              onTap: () => open('Weight', 'weight', ['< 50 kg', '50–70 kg', '70–90 kg', '> 90 kg'])),
          NavRow(title: 'Height', value: s.pref('height'),
              onTap: () => open('Height', 'height', ['< 160 cm', '160–175 cm', '175–190 cm', '> 190 cm'])),
          NavRow(title: 'Gender', value: s.pref('gender'),
              onTap: () => open('Gender', 'gender', ['Female', 'Male', 'Other', 'Prefer not to say'])),
          NavRow(title: 'Year of birth', value: s.pref('birth'),
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
                Text(body, style: const TextStyle(color: Colors.white60, height: 1.4)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: s.pref(key) == 'true',
                  activeColor: AppTheme.accent,
                  title: const Text('I agree'),
                  onChanged: (v) => s.setPref(key, '${v ?? false}'),
                ),
                const Divider(color: Colors.white12),
              ]),
            );
        return SettingsPage(title: 'Consent and privacy', children: [
          block('Store sleep data online', 'Needed for online backup and moving to a new phone.', 'consent_storage'),
          block('Share sounds', 'Let us use anonymous sound clips to improve snore and sound detection.', 'consent_sounds'),
          block('Improve the product', 'Share anonymous usage statistics so we can see which features help.', 'consent_product'),
        ]);
      });
}

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return SettingsPage(title: 'Database', children: [
      NavRow(icon: Icons.share, title: 'Export database to CSV', onTap: () async {
        final rows = ['start,end,quality,asleep_min,in_bed_min,snore_min,steps'];
        for (final n in s.nights) {
          rows.add('${n.wentToBed.toIso8601String()},${n.wokeUp.toIso8601String()},${n.quality},'
              '${n.asleepMinutes},${n.inBedMinutes},${n.snoreMinutes},${n.steps}');
        }
        try {
          final f = File('${Directory.systemTemp.path}/sleep_export.csv')..writeAsStringSync(rows.join('\n'));
          if (context.mounted) toast(context, 'Exported ${s.nights.length} nights to ${f.path}');
        } catch (_) {
          if (context.mounted) toast(context, 'Export failed');
        }
      }),
      // Prototype helper: populate every screen without tracking for real.
      NavRow(icon: Icons.science, title: 'Load sample nights (prototype)', onTap: () {
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
            child: const Text('Erase database', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
        ),
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
        PrefRadioList(header: 'Keep downloaded files for', prefKey: 'sleep_aid_keep',
            options: ['1 night', '20 nights (recommended)', 'Forever']),
        PrefRadioList(
            header: 'Fade out ambient sounds after',
            prefKey: 'sleep_aid_fade',
            options: ['Smart (recommended)', '10 minutes', '20 minutes', '30 minutes', '45 minutes', '60 minutes',
              '90 minutes', 'All night']),
      ]);
}

class SleepNotesPage extends StatelessWidget {
  const SleepNotesPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsPage(title: 'Sleep notes', children: [
        const _Radio('sleep_notes', ['Show', 'Hide']),
        const Divider(indent: 20, endIndent: 20, color: Colors.white12),
        NavRow(title: 'Edit sleep notes', onTap: () => push(context, const EditSleepNotesPage())),
        NavRow(title: 'Home location', onTap: () => toast(context, 'Used to tag nights away from home')),
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
            icon: const Icon(Icons.arrow_back, color: AppTheme.accent), onPressed: () => Navigator.pop(context)),
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
              leading: const Icon(Icons.add_circle, color: Colors.greenAccent),
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
                    icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                    onPressed: () {
                      s.sleepNotes.remove(n);
                      s.notesChanged();
                    },
                  ),
                  title: Text(n),
                  trailing: const Icon(Icons.drag_handle, color: AppTheme.accent),
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
      art: Icons.record_voice_over, artAsset: 'assets/images/who_is_snoring_fallback.jpg');
}

// ── Gift / Help ─────────────────────────────────────────────────────────────

class BenefitsPage extends StatelessWidget {
  const BenefitsPage({super.key});
  @override
  Widget build(BuildContext context) => const SettingsPage(title: 'Benefits', children: [
        Padding(
          padding: EdgeInsets.fromLTRB(32, 40, 32, 60),
          child: Text('Offers and gifts for you and your friends will show up here.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Center(child: CircleArt(icon: Icons.card_giftcard, size: 220,
            colors: [Color(0xFFFF8A4C), Color(0xFF7A2E10)])),
      ]);
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  static const topics = {
    'Getting started': [
      ('Where should I put my phone?', 'Next to your bed, screen down and charging. With the accelerometer, on the mattress.'),
      ('Do I need to be online?', 'No. Tracking and analysis run on your phone.'),
    ],
    'Top questions': [
      ('Why did the alarm ring before my alarm time?', 'The smart alarm wakes you in light sleep within your wake-up phase.'),
      ('How is quality calculated?', 'From time asleep, how often you woke, and deeper sleep.'),
    ],
    'Subscriptions': [
      ('How do I cancel my trial?', 'In your phone\'s app store subscriptions, before the trial ends.'),
    ],
    'Account settings': [
      ('How do I export my data?', 'Profile › More › Database › Export database to CSV.'),
    ],
  };
  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: 'Help', children: [
      Container(
        color: const Color(0xFF2A6C80),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: const Column(children: [
          Text('Help center', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Search',
              hintStyle: TextStyle(color: Colors.black45),
              prefixIcon: Icon(Icons.search, color: Colors.black45),
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
            ),
            style: TextStyle(color: Colors.black),
          ),
        ]),
      ),
      for (final t in topics.entries)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                side: const BorderSide(color: AppTheme.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
            onPressed: () => push(
                context,
                SettingsPage(title: t.key, children: [
                  for (final qa in t.value)
                    ExpansionTile(title: Text(qa.$1), children: [
                      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(qa.$2)),
                    ]),
                ])),
            child: Text(t.key, style: const TextStyle(color: AppTheme.accent, fontSize: 16)),
          ),
        ),
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
  const SimpleRadioPage(this.title, this.prefKey, this.options,
      {super.key, this.about, this.header, this.art, this.artAsset});
  @override
  Widget build(BuildContext context) => SettingsPage(title: title, children: [
        PrefRadioList(header: header, prefKey: prefKey, options: options),
        if (about != null)
          AboutBlock(about!, art: art == null ? null : CircleArt(asset: artAsset, icon: art!)),
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
                      color: AppTheme.accent, size: 22),
                  const SizedBox(width: 16),
                  Text('$o$suffix', style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
        ]),
      ));
}
