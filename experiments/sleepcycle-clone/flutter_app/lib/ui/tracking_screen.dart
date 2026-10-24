import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../alarm/alarm_plan.dart';
import '../app_state.dart';
import '../data/night.dart';
import '../backend/backend.dart';
import '../data/recorded_night.dart';
import '../device/device_sensors.dart';
import '../device/health_connect.dart';
import '../device/location.dart';
import '../device/notifications.dart';
import '../device/tracking_service.dart';
import '../sensing/live_tracker.dart';
import '../sensing/sleep_tracker.dart';
import '../theme.dart';
import 'alarm_screen.dart';
import 'sleep_aid_sheet.dart';
import 'widgets/common.dart';
import 'widgets/time_wheel.dart';

/// The overnight screen: sleep-aid pill, tonight's moon, a large dimmed
/// clock, the alarm window (tap to change it), and a slide-up "Stop".
///
/// The alarm lives here: a foreground service keeps the app running with the
/// screen off, the smart alarm watches the night's movement inside the wake
/// window and rings at the lightest moment (or at the alarm time), and an OS
/// alarm-clock notification is scheduled as a backup in case the app is
/// killed. A low battery warns, then rings early before the phone dies.
///
/// While open, [LiveTracker] records accelerometer movement and (in
/// microphone mode) sound levels. Stopping analyses the recording into a
/// night in the Journal, adding steps (Health Connect) and morning weather
/// (API). Sessions under [minMinutes] are too short to analyse — as in the
/// original — so for testing you can save a replayed sample night instead.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const minMinutes = 20;
  final _tracker = LiveTracker(
      useMicrophone: AppState.I.pref('motion_detection').startsWith('Microphone'),
      clipDir: AppState.I.clipDirForTonight());
  late Timer _clock;
  Timer? _alarmTick, _batteryTick;
  late AlarmPlan _plan;
  DateTime _now = DateTime.now();
  double _drag = 0;
  bool _stopping = false;
  bool _ringing = false;
  bool _onsetSeen = false;
  bool _batteryWarned = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _now = DateTime.now()));
    _tracker.onEpoch = (_) {
      if (!_onsetSeen && _tracker.seemsAsleep) {
        _onsetSeen = true;
        AppState.I.sleepOnsetDetected();
      }
    };
    _tracker.start();
    _plan = _makePlan();
    _armAlarm();
    _batteryTick = Timer.periodic(const Duration(minutes: 5), (_) => _checkBattery());
    _checkBattery();
  }

  @override
  void dispose() {
    _clock.cancel();
    _alarmTick?.cancel();
    _batteryTick?.cancel();
    if (!_stopping) {
      _tracker.stop();
      Notifications.I.cancel(Notifications.alarmId);
      TrackingService.stop();
    }
    super.dispose();
  }

  AlarmPlan _makePlan() {
    final s = AppState.I;
    final test = s.takeTestAlarm();
    if (test != null) {
      return AlarmPlan(mode: 1, end: test, windowMinutes: 0, snooze: s.pref('snooze'));
    }
    return AlarmPlan.next(DateTime.now(),
        hour: s.alarmHour,
        minute: s.alarmMinute,
        mode: s.alarmMode,
        windowMinutes: s.windowMinutes,
        snooze: s.pref('snooze'));
  }

  Future<void> _armAlarm() async {
    _alarmTick?.cancel();
    await Notifications.I.cancel(Notifications.alarmId);
    final text = _plan.enabled ? 'Alarm $_alarmLabel' : 'No alarm set. Swipe up in the app to stop.';
    await TrackingService.start(text, microphone: _tracker.useMicrophone);
    if (!_plan.enabled) return;
    await Notifications.I.requestPermission(alarm: true);
    // the OS rings at the latest time if this app isn't around to do it
    await Notifications.I.scheduleAlarmBackup(_plan.end.add(const Duration(seconds: 30)));
    _alarmTick = Timer.periodic(const Duration(seconds: 5), (_) => _checkAlarm());
  }

  void _checkAlarm() {
    if (_ringing || _stopping) return;
    final m = _tracker.movementSoFar();
    final recent = m.isEmpty ? 0.0 : m.sublist(math.max(0, m.length - 2)).reduce(math.max);
    if (_plan.shouldRing(DateTime.now(), recentMovement: recent, nightMovement: m)) _ringAlarm();
  }

  Future<void> _ringAlarm() async {
    if (_ringing || _stopping || !mounted) return;
    _ringing = true;
    _alarmTick?.cancel();
    await Notifications.I.cancel(Notifications.alarmId);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AlarmScreen(plan: _plan)));
    _stop(fromAlarm: true);
  }

  Future<void> _checkBattery() async {
    if (AppState.I.pref('battery_warning') != 'On' || _stopping) return;
    final b = await DeviceSensors.battery();
    if (b == null || b.$2) {
      if (mounted && _banner != null) setState(() => _banner = null);
      return;
    }
    final level = b.$1;
    if (level <= 15 && !_batteryWarned) {
      _batteryWarned = true;
      Notifications.I.showBatteryWarning(level);
      if (mounted) setState(() => _banner = 'Battery $level%. Plug in your phone to keep tracking.');
    }
    // ring before the phone dies rather than not at all
    if (level <= 5 && _plan.enabled && !_ringing) _ringAlarm();
  }

  String get _alarmLabel {
    if (!_plan.enabled) return 'Off';
    final end = fmtDt(_plan.end);
    if (!_plan.smart) return end;
    return '${fmtDt(_plan.windowStart).split(' ').first} - $end';
  }

  Future<void> _changeAlarm() async {
    final s = AppState.I;
    var h = s.alarmHour, m = s.alarmMinute;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Cancel', style: TextStyle(color: context.palette.accent, fontSize: 16))),
          const Expanded(
              child: Text('Change alarm',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Done', style: TextStyle(color: context.palette.accent, fontSize: 16))),
        ]),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: TimeWheel(
              hour: h,
              minute: m,
              onChanged: (hh, mm) {
                h = hh;
                m = mm;
              }),
        ),
      ]),
    );
    if (ok == true) {
      s.setAlarm(h, m);
      setState(() => _plan = _makePlan());
      _armAlarm();
    }
  }

  Future<void> _stop({bool fromAlarm = false}) async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _alarmTick?.cancel();
    await Notifications.I.cancel(Notifications.alarmId);
    await TrackingService.stop();
    await _tracker.stop();
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    late final Night night;
    if (_tracker.elapsed.inMinutes >= minMinutes) {
      night =
          Night.fromResult(_tracker.analyze(), snoreMinutes: _tracker.soundMinutes, coughs: _tracker.coughs, real: true)
            ..clips.addAll(_tracker.clips)
            ..snoreSpans = _tracker.snoreSpans
            ..lightLux = _tracker.medianLux
            ..noiseDb = _tracker.medianNoiseDb;
    } else {
      if (!mounted) return;
      final sample = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Too short to analyze'),
          content: Text('You tracked ${_tracker.elapsed.inMinutes} min. Nights need at least '
              '$minMinutes min.\n\nFor testing, you can save a sample night instead.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Discard')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save sample night')),
          ],
        ),
      );
      if (sample != true) {
        AppState.I.pauseSleepAid();
        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
        return;
      }
      night = await _sampleNight(seed);
    }
    // steps from Health Connect, written back as a sleep session if enabled
    if (AppState.I.pref('health_connect') == 'On') {
      night.steps = await HealthConnect.I.stepsBefore(night.wokeUp) ?? night.steps;
      await HealthConnect.I.writeSleep(night.session);
    }
    // nights away from the saved home location get the Travel note
    final home = AppState.I.pref('home_location');
    (double, double)? loc;
    if (home.isNotEmpty || Backend.I.user != null) loc = await coarseLocation();
    if (home.isNotEmpty && loc != null) {
      final h = home.split(',').map(double.parse).toList();
      if (_km(h[0], h[1], loc.$1, loc.$2) > 50) night.notes.add('Travel');
    }
    // real morning weather via the API when signed in and location is allowed
    if (Backend.I.user != null) {
      night.weatherF = null;
      if (loc != null) {
        try {
          final w = await Backend.I.weather(loc.$1, loc.$2);
          night.weatherF = (w?['tempF'] as num?)?.round();
          night.weatherCode = (w?['code'] as num?)?.toInt();
        } catch (_) {}
      }
    }
    AppState.I
      ..addNight(night)
      ..pauseSleepAid()
      ..goTab(2) // Journal
      ..pruneClips();
    // morning flow (wake-up mood, alertness test) runs on the tabs
    if (fromAlarm) AppState.I.morning.value = night;
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  /// Replay of the bundled recorded night, or the simulated accelerometer
  /// pipeline when the recording isn't available.
  Future<Night> _sampleNight(int seed) async {
    final recorded = RecordedNight.cached;
    if (recorded != null) return recorded.toNight(DateTime.now(), seed: seed);
    final hours = 7 + math.Random(seed).nextInt(2);
    final result = await SleepTracker().run(
      SimulatedNight(hours: hours, seed: seed),
      startedAt: DateTime.now().subtract(Duration(hours: hours)),
    );
    return Night.fromResult(result, seed: seed);
  }

  @override
  Widget build(BuildContext context) {
    final moonIndex = moonPhaseIndex(_now);
    return Scaffold(
      body: StarryBackground(
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 12),
            const SleepAidPill(),
            if (_banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  Icon(Icons.battery_alert, color: context.palette.warn),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_banner!, style: TextStyle(color: context.palette.warn))),
                ]),
              ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.only(right: 140),
              child: SizedBox(
                width: 84,
                height: 84,
                child: Image.asset('assets/free/images/moon_${moonIndex.toString().padLeft(2, '0')}.webp',
                    errorBuilder: (_, __, ___) => const _Moon()),
              ),
            ),
            const SizedBox(height: 40),
            Text(fmtDt(_now),
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: context.palette.textMuted)),
            GestureDetector(
              onTap: _plan.enabled ? _changeAlarm : null,
              child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Alarm  '),
                    TextSpan(text: _alarmLabel, style: const TextStyle(decoration: TextDecoration.underline)),
                  ]),
                  style: TextStyle(fontSize: 18, color: context.palette.textMuted)),
            ),
            const Spacer(),
            if (_stopping)
              Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Analyzing your night…', style: TextStyle(color: context.palette.textMuted)),
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
                  child: SizedBox(
                    width: 160,
                    height: 90,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.keyboard_arrow_up, color: context.palette.textMuted, size: 32),
                      Text('Stop', style: TextStyle(fontSize: 20, color: context.palette.textMuted)),
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
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [context.palette.rem, context.palette.deep]),
          boxShadow: [BoxShadow(color: context.palette.glow, blurRadius: 30)],
        ),
      );
}

/// Tonight's moon as one of 30 frames from new (0) through full (15) and
/// back, from the mean synodic month counted from a known new moon.
int moonPhaseIndex(DateTime t) {
  const synodic = 29.530588853;
  final newMoon = DateTime.utc(2000, 1, 6, 18, 14);
  final days = t.toUtc().difference(newMoon).inMinutes / 1440.0;
  final age = days % synodic;
  return (age / synodic * 30).round() % 30;
}
