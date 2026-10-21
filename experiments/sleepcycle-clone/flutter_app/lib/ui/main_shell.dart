import 'package:flutter/material.dart';
import '../theme.dart';
import 'journal_tab.dart';
import 'profile_tab.dart';
import 'programs_tab.dart';
import 'sleep_tab.dart';
import 'statistics_tab.dart';
import 'widgets/common.dart';

/// Root with the original's five-tab bottom bar, in the same order:
/// Sleep · Programs · Journal · Statistics · Profile. The selected tab lives
/// in AppState so flows (e.g. stopping a night) can switch tabs.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const _tabs = [
    (Icons.nightlight_round, 'Sleep'),
    (Icons.change_history, 'Programs'),
    (Icons.monitor_heart_outlined, 'Journal'),
    (Icons.bar_chart, 'Statistics'),
    (Icons.person, 'Profile'),
  ];

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
            backgroundColor: const Color(0xFF0A1B26),
            indicatorColor: Colors.transparent,
            height: 68,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final t in _tabs)
                NavigationDestination(
                  icon: Icon(t.$1, color: const Color(0xFF5F8396)),
                  selectedIcon: Icon(t.$1, color: AppTheme.accent),
                  label: t.$2,
                ),
            ],
          ),
        ));
  }
}
