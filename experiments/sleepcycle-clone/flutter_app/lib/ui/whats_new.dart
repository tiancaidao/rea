import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'widgets/common.dart';

/// One-time "What's new" sheet for people who already track, listing the
/// features this version added (the original shows one per release).
const whatsNewVersion = 'alarm-1';

const _items = [
  (
    Icons.alarm,
    'Smart alarm that really rings',
    'Wakes you in light sleep inside your window. Snooze by tapping twice or picking the phone up.'
  ),
  (Icons.bolt, 'Morning alertness test', 'A one-minute game that shows how sharp you are today.'),
  (Icons.graphic_eq, 'Sounds from your night', 'Listen back to snoring and other sounds in the Journal.'),
  (Icons.notifications_active, 'Bedtime reminders', 'Get a nudge to start tracking. Set it in Profile.'),
];

Future<void> maybeShowWhatsNew(BuildContext context) async {
  final s = AppState.I;
  if (s.nights.isEmpty || s.pref('whats_new_seen') == whatsNewVersion) return;
  s.setPref('whats_new_seen', whatsNewVersion);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("What's new", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (final it in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(it.$1, color: c.palette.accent, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(it.$3, style: TextStyle(color: c.palette.textMuted, height: 1.35)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Center(child: PillButton('Got it', width: 200, onPressed: () => Navigator.pop(c))),
      ]),
    ),
  );
}
