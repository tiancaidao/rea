import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'sleep_aid_sheet.dart';
import 'tracking_screen.dart';
import 'widgets/common.dart';
import 'widgets/illustrations.dart';
import 'widgets/looping_video.dart';
import 'widgets/time_wheel.dart';

/// Sleep tab: sleep-aid pill, alarm time wheel, and a 3-page pager for the
/// alarm mode (smart wake-up window · regular alarm · no alarm). The Start
/// button's color tracks the mode. Start → two "Remember" tips → tracking.
class SleepTab extends StatefulWidget {
  const SleepTab({super.key});
  @override
  State<SleepTab> createState() => _SleepTabState();
}

class _SleepTabState extends State<SleepTab> {
  late final _pager = PageController(initialPage: AppState.I.alarmMode);

  String _describe(AppState s, int mode) {
    final end = fmtTime(s.alarmHour, s.alarmMinute);
    final startT = DateTime(2000, 1, 1, s.alarmHour, s.alarmMinute).subtract(Duration(minutes: s.windowMinutes));
    switch (mode) {
      case 0:
        return 'Wake up easy between\n${fmtDt(startT).split(' ').first} - $end';
      case 1:
        return 'No wake-up window.\nAlarm will go off at $end';
      default:
        return 'No alarm.\nOnly your sleep is analyzed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StarryBackground(
      child: SafeArea(
        child: Watch((context, s) => Column(children: [
              const SizedBox(height: 12),
              const SleepAidPill(),
              const Spacer(flex: 3),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: s.alarmMode == 2 ? 0 : 1,
                child: IgnorePointer(
                  ignoring: s.alarmMode == 2,
                  child: TimeWheel(
                    hour: s.alarmHour,
                    minute: s.alarmMinute,
                    onChanged: s.setAlarm,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 150,
                child: PageView.builder(
                  controller: _pager,
                  itemCount: 3,
                  onPageChanged: s.setAlarmMode,
                  itemBuilder: (context, i) => Column(children: [
                    Text(_describe(s, i),
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.35)),
                    const SizedBox(height: 22),
                    PillButton('Start',
                        width: 150,
                        color: [null, context.palette.light, context.palette.deep][i],
                        onPressed: () => startSleep(context)),
                  ]),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.all(4),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == s.alarmMode ? context.palette.accent : context.palette.surfaceHi,
                    ),
                  ),
              ]),
              const Spacer(flex: 2),
            ])),
      ),
    );
  }
}

/// Start flow shared by the Sleep tab: optional placement/snooze tips, then
/// the full-screen tracking view.
Future<void> startSleep(BuildContext context) async {
  if (AppState.I.pref('placement_reminders') == 'On') {
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _RememberSheet()),
    );
    if (go != true) return;
  }
  if (!context.mounted) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen()));
}

class _RememberSheet extends StatefulWidget {
  const _RememberSheet();
  @override
  State<_RememberSheet> createState() => _RememberSheetState();
}

class _RememberSheetState extends State<_RememberSheet> {
  int _step = 0;
  @override
  Widget build(BuildContext context) {
    final mic = AppState.I.pref('motion_detection').startsWith('Microphone');
    final steps = [
      (
        mic ? Art.placementMic : Art.placementBed,
        Icons.phone_android,
        mic
            ? 'Put the phone by your bed, screen down, and keep it charging.'
            : 'Put the phone on the mattress near your pillow and keep it charging.',
        'Next'
      ),
      (Art.snooze, Icons.touch_app, 'To snooze, tap the phone twice\nor lift it up.', 'OK'),
    ];
    final st = steps[_step];
    return Column(children: [
      Row(children: [
        IconButton(
          icon: Icon(_step == 0 ? Icons.keyboard_arrow_down : Icons.chevron_left,
              color: context.palette.accent, size: 30),
          onPressed: () => _step == 0 ? Navigator.pop(context, false) : setState(() => _step = 0),
        ),
        const Expanded(
            child: Text('Remember',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        const SizedBox(width: 48),
      ]),
      const Divider(height: 1),
      const Spacer(),
      if (_step == 1 && mic)
        SizedBox(
          width: 260,
          height: 260,
          child: ClipOval(
            child: LoopingVideo(
              asset: 'assets/video/mic_snooze_reminder.mp4',
              fallback: CircleArt(art: st.$1, icon: st.$2, size: 260),
            ),
          ),
        )
      else
        CircleArt(art: st.$1, icon: st.$2, size: 260),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(st.$3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.35)),
      ),
      const SizedBox(height: 20),
      PillButton(st.$4, width: 180, onPressed: () {
        if (_step == 0) {
          setState(() => _step = 1);
        } else {
          Navigator.pop(context, true);
        }
      }),
      const SizedBox(height: 28),
    ]);
  }
}
