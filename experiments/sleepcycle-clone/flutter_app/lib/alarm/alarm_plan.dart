import 'dart:math' as math;
import '../core/sleep_algorithms.dart';

/// Tonight's alarm, decided when tracking starts: the latest wake-up time
/// ([end]) and, for the smart alarm, the window before it in which a light
/// moment may trigger it early. Plain Dart so the firing and snooze rules are
/// unit-tested without a device.
class AlarmPlan {
  final int mode; // 0 smart window · 1 regular alarm · 2 no alarm
  final DateTime end;
  final int windowMinutes;
  final String snooze; // 'Smart (recommended)' · 'Regular' · 'Off'
  const AlarmPlan({required this.mode, required this.end, required this.windowMinutes, required this.snooze});

  /// The next occurrence of [hour]:[minute] after [now]. An alarm set for a
  /// time that already passed today rings tomorrow.
  factory AlarmPlan.next(DateTime now,
      {required int hour, required int minute, required int mode, required int windowMinutes, required String snooze}) {
    var end = DateTime(now.year, now.month, now.day, hour, minute);
    if (!end.isAfter(now)) end = end.add(const Duration(days: 1));
    return AlarmPlan(mode: mode, end: end, windowMinutes: windowMinutes, snooze: snooze);
  }

  bool get enabled => mode != 2;
  bool get smart => mode == 0;
  DateTime get windowStart => smart ? end.subtract(Duration(minutes: windowMinutes)) : end;
  bool get canSnooze => snooze != 'Off';

  /// Whether the alarm should start ringing at [now]. Inside the smart window
  /// the night's own movement decides (lightest moment, threshold easing
  /// towards the end of the window, as in [SmartAlarm]); at [end] it always
  /// rings.
  bool shouldRing(DateTime now, {double recentMovement = 0, List<double> nightMovement = const []}) {
    if (!enabled) return false;
    if (!now.isBefore(end)) return true;
    if (!smart || now.isBefore(windowStart) || nightMovement.length < 20) return false;
    final minute = now.difference(windowStart).inMinutes;
    return SmartAlarm(windowMinutes: windowMinutes).shouldFire(minute, recentMovement, nightMovement);
  }

  /// How long to snooze when snoozed at [now]. Regular: a fixed 9 minutes.
  /// Smart: the remaining time to the wake-up time is halved each snooze
  /// (never under 1 minute, never past [end] by more than a minute), so you
  /// still get up on time; after [end] it falls back to short 5-minute naps.
  Duration snoozeFor(DateTime now) {
    if (snooze == 'Regular') return const Duration(minutes: 9);
    final left = end.difference(now);
    if (left.inSeconds <= 60) return const Duration(minutes: 5);
    final half = Duration(seconds: math.max(60, left.inSeconds ~/ 2));
    return half > const Duration(minutes: 9) ? const Duration(minutes: 9) : half;
  }
}
