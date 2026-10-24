import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';
import '../alarm/alarm_plan.dart';
import '../app_state.dart';
import '../device/notifications.dart';
import 'alarm_screen.dart';
import 'alertness_game.dart';
import 'journal_tab.dart';
import 'morning_flow.dart';
import 'profile_tab.dart';
import 'programs_tab.dart';
import 'sleep_tab.dart';
import 'statistics_tab.dart';
import 'welcome_screen.dart';
import 'whats_new.dart';
import 'widgets/common.dart';

/// Root with the original's five-tab bottom bar, in the same order:
/// Sleep · Programs · Journal · Statistics · Profile. The selected tab lives
/// in AppState so flows (e.g. stopping a night) can switch tabs.
///
/// It also routes what arrives from outside the tabs: the morning flow after
/// the alarm, taps on notifications (the backup alarm, reminders), and the
/// one-time "What's new" sheet. Launcher shortcuts (long-press the icon) and
/// sleepclone:// links arrive through the same route as notification taps.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static const _tabs = [
    (Icons.nightlight_round, 'Sleep'),
    (Icons.change_history, 'Programs'),
    (Icons.monitor_heart_outlined, 'Journal'),
    (Icons.bar_chart, 'Statistics'),
    (Icons.person, 'Profile'),
  ];

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _initShortcuts();
    AppState.I.morning.addListener(_onMorning);
    Notifications.I.tapped.addListener(_onNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onNotification();
      if (mounted) maybeShowWhatsNew(context);
    });
  }

  @override
  void dispose() {
    AppState.I.morning.removeListener(_onMorning);
    Notifications.I.tapped.removeListener(_onNotification);
    _links?.cancel();
    super.dispose();
  }

  void _initShortcuts() {
    void route(String r) => Notifications.I.tapped.value = r;
    try {
      const qa = QuickActions();
      qa.initialize(route);
      qa.setShortcutItems(const [
        ShortcutItem(type: 'start_alarm', localizedTitle: 'Start with alarm', icon: 'ic_shortcut_alarm'),
        ShortcutItem(type: 'start_no_alarm', localizedTitle: 'Start without alarm', icon: 'ic_shortcut_sleep'),
      ]);
    } catch (_) {}
    try {
      // sleepclone://journal, sleepclone://start, … (the host names the route)
      _links = AppLinks().uriLinkStream.listen((u) {
        final r = u.host.isNotEmpty ? u.host : u.pathSegments.firstOrNull;
        if (r != null) route(r);
      });
    } catch (_) {}
  }

  void _onMorning() {
    final night = AppState.I.morning.value;
    if (night == null) return;
    AppState.I.morning.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runMorningFlow(context, night);
    });
  }

  Future<void> _onNotification() async {
    final payload = Notifications.I.tapped.value;
    if (payload == null || !mounted) return;
    Notifications.I.tapped.value = null;
    final s = AppState.I;
    switch (payload) {
      case 'alarm':
        // the OS backup alarm rang (the app wasn't tracking): stop or snooze here
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AlarmScreen(
                    plan: AlarmPlan(mode: 1, end: DateTime.now(), windowMinutes: 0, snooze: s.pref('snooze')))));
      case 'alertness':
        s.goTab(2);
        final n = s.currentNight;
        if (n != null && alertnessAvailable(n) && mounted) push(context, AlertnessGame(night: n));
      case 'weekly':
        s.goTab(2);
      case 'sleep':
        s.goTab(0);
      case 'premium':
        s.goTab(4);
        push(context, const TrialScreen());
      case 'start_alarm' || 'start':
        s.goTab(0);
        if (s.alarmMode == 2) s.setAlarmMode(0);
        await startSleep(context);
      case 'start_no_alarm' || 'start-no-alarm':
        s.goTab(0);
        s.setAlarmMode(2);
        await startSleep(context);
      case 'programs':
        s.goTab(1);
      case 'journal':
        s.goTab(2);
      case 'statistics':
        s.goTab(3);
      case 'profile':
        s.goTab(4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context, s) => Scaffold(
          body: IndexedStack(index: s.tab, children: const [
            SleepTab(),
            ProgramsTab(),
            JournalTab(),
            StatisticsTab(),
            ProfileTab(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: s.tab,
            onDestinationSelected: s.goTab,
            height: 68,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final t in MainShell._tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2),
            ],
          ),
        ));
  }
}
