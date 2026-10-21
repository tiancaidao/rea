// Data models for the sleep tracker.

class PhasePoint {
  final int epoch; // epoch index (30s each)
  final String phase; // deep | light | rem | awake
  PhasePoint(this.epoch, this.phase);

  factory PhasePoint.fromJson(Map<String, dynamic> j) =>
      PhasePoint(j['t'] as int, j['phase'] as String);
  Map<String, dynamic> toJson() => {'t': epoch, 'phase': phase};
}

class SleepSession {
  final DateTime startedAt;
  final DateTime endedAt;
  final List<PhasePoint> phases;
  final int snoreEvents;
  final double snorePercent;
  final int sleepScore;

  SleepSession({
    required this.startedAt,
    required this.endedAt,
    required this.phases,
    required this.snoreEvents,
    required this.snorePercent,
    required this.sleepScore,
  });

  Duration get timeInBed => endedAt.difference(startedAt);

  int get minutesAsleep =>
      phases.where((p) => p.phase != 'awake').length * 30 ~/ 60;

  Map<String, int> get phaseMinutes {
    final m = {'deep': 0, 'light': 0, 'rem': 0, 'awake': 0};
    for (final p in phases) {
      m[p.phase] = (m[p.phase] ?? 0) + 30;
    }
    return m.map((k, v) => MapEntry(k, v ~/ 60));
  }

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'endedAt': endedAt.millisecondsSinceEpoch,
        'phases': phases.map((p) => p.toJson()).toList(),
        'snoreEvents': snoreEvents,
        'snorePercent': snorePercent,
        'sleepScore': sleepScore,
      };
}

class AlarmSettings {
  TimeOfDayLike alarmTime;
  int windowMinutes;
  bool smartAlarmEnabled;
  AlarmSettings({
    required this.alarmTime,
    this.windowMinutes = 30,
    this.smartAlarmEnabled = true,
  });
}

/// Minimal time-of-day holder so models stay free of Flutter imports.
class TimeOfDayLike {
  final int hour;
  final int minute;
  const TimeOfDayLike(this.hour, this.minute);
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
