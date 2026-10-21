import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/night.dart';
import '../data/recorded_night.dart';
import '../sensing/sleep_tracker.dart';
import '../theme.dart';
import 'sleep_aid_sheet.dart';
import 'widgets/common.dart';
import 'widgets/time_wheel.dart';

/// The overnight screen: sleep-aid pill, tonight's moon, a large dimmed
/// clock, the alarm window (tap to change it), and a slide-up "Stop".
///
/// Stopping finishes the night. Real sensing is native and not wired yet, so
/// the night is produced by running the analysis pipeline on a SimulatedNight;
/// the result lands in the Journal tab exactly like a tracked night would.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late Timer _clock;
  DateTime _now = DateTime.now();
  double _drag = 0;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  String get _alarmLabel {
    final s = AppState.I;
    final end = fmtTime(s.alarmHour, s.alarmMinute);
    if (s.alarmMode == 2) return 'Off';
    if (s.alarmMode == 1) return end;
    final start = DateTime(2000, 1, 1, s.alarmHour, s.alarmMinute)
        .subtract(Duration(minutes: s.windowMinutes));
    return '${fmtDt(start).split(' ').first} - $end';
  }

  Future<void> _changeAlarm() async {
    final s = AppState.I;
    var h = s.alarmHour, m = s.alarmMinute;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF0B1C27),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.accent, fontSize: 16))),
          const Expanded(
              child: Text('Change alarm',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Done', style: TextStyle(color: AppTheme.accent, fontSize: 16))),
        ]),
        const Divider(height: 1, color: Colors.white12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: TimeWheel(hour: h, minute: m, onChanged: (hh, mm) {
            h = hh;
            m = mm;
          }),
        ),
      ]),
    );
    if (ok == true) {
      s.setAlarm(h, m);
      setState(() {});
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    // Native sensing isn't wired yet. Prefer replaying the bundled recorded
    // night (jittered) through our staging; else run the accelerometer
    // pipeline on a SimulatedNight.
    final recorded = RecordedNight.cached;
    late final Night night;
    if (recorded != null) {
      await Future.delayed(const Duration(milliseconds: 600));
      night = recorded.toNight(DateTime.now(), seed: seed);
    } else {
      final hours = 7 + math.Random(seed).nextInt(2);
      final result = await SleepTracker().run(
        SimulatedNight(hours: hours, seed: seed),
        startedAt: DateTime.now().subtract(Duration(hours: hours)),
      );
      night = Night.fromResult(result, seed: seed);
    }
    AppState.I
      ..addNight(night)
      ..pauseSleepAid()
      ..goTab(2); // Journal
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final moonIndex = (_now.day % 30);
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 12),
            const SleepAidPill(),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.only(right: 140),
              child: SizedBox(
                width: 84,
                height: 84,
                child: Image.asset('assets/images/night_moon_$moonIndex.webp',
                    errorBuilder: (_, __, ___) => const _Moon()),
              ),
            ),
            const SizedBox(height: 40),
            Text(fmtDt(_now),
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: Color(0xFF8FB8C8))),
            GestureDetector(
              onTap: AppState.I.alarmMode == 2 ? null : _changeAlarm,
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Alarm  '),
                TextSpan(
                    text: _alarmLabel,
                    style: const TextStyle(decoration: TextDecoration.underline)),
              ]), style: const TextStyle(fontSize: 18, color: Color(0xFF8FB8C8))),
            ),
            const Spacer(),
            if (_stopping)
              const Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Analyzing your night…', style: TextStyle(color: Colors.white70)),
              ])
            else
              GestureDetector(
                onVerticalDragUpdate: (d) => setState(() => _drag = (_drag - d.delta.dy).clamp(0, 200)),
                onVerticalDragEnd: (d) {
                  if (_drag > 90 || (d.primaryVelocity ?? 0) < -600) {
                    _stop();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                onTap: () => toast(context, 'Swipe up to stop'),
                child: Transform.translate(
                  offset: Offset(0, -_drag),
                  child: const SizedBox(
                    width: 160,
                    height: 90,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.keyboard_arrow_up, color: Color(0xFF8FB8C8), size: 32),
                      Text('Stop', style: TextStyle(fontSize: 20, color: Color(0xFF8FB8C8))),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 60),
          ]),
        ),
      ),
    );
  }
}

class _Moon extends StatelessWidget {
  const _Moon();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFFB9D9E6), Color(0xFF3B6F86)]),
          boxShadow: [BoxShadow(color: Color(0x553FC1E0), blurRadius: 30)],
        ),
      );
}
