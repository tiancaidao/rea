import 'dart:math' as math;
import 'models.dart';
import '../sensing/sleep_tracker.dart';

/// One tracked night as the Journal shows it: the analysed session plus the
/// extras logged around it (mood, sleep notes) and the context metrics the
/// stat grid displays. Steps / weather / breathing are mocked until the
/// matching integrations (Health Connect, a weather API, a breathing model)
/// are wired in.
class Night {
  final SleepSession session;
  int? mood; // 0 = bad, 1 = okay, 2 = good
  final Set<String> notes;
  int? steps; // null until known (Health Connect not connected)
  int? weatherF; // null until known (no location / backend off)
  final int snoreMinutes;
  final int coughs;
  final double breathingPerHour;
  final int regularity; // 0..100, consistency of bed/wake times

  Night({
    required this.session,
    this.mood,
    Set<String>? notes,
    this.steps,
    required this.weatherF,
    required this.snoreMinutes,
    required this.coughs,
    required this.breathingPerHour,
    required this.regularity,
  }) : notes = notes ?? {};

  DateTime get wentToBed => session.startedAt;
  DateTime get wokeUp => session.endedAt;
  int get quality => session.sleepScore;
  int get inBedMinutes => session.timeInBed.inMinutes;
  int get asleepMinutes => session.minutesAsleep;

  int get asleepAfterMinutes {
    final i = session.phases.indexWhere((p) => p.phase != 'awake');
    return i < 0 ? 0 : i * 30 ~/ 60;
  }

  /// Night "belongs" to the morning it ends on.
  DateTime get day => DateTime(wokeUp.year, wokeUp.month, wokeUp.day);

  Map<String, dynamic> toJson() => {
        'session': session.toJson(),
        'mood': mood,
        'notes': notes.toList(),
        'steps': steps,
        'weatherF': weatherF,
        'snoreMinutes': snoreMinutes,
        'coughs': coughs,
        'breathingPerHour': breathingPerHour,
        'regularity': regularity,
      };

  factory Night.fromJson(Map<String, dynamic> j) {
    final s = j['session'] as Map<String, dynamic>;
    return Night(
      session: SleepSession(
        startedAt: DateTime.fromMillisecondsSinceEpoch(s['startedAt'] as int),
        endedAt: DateTime.fromMillisecondsSinceEpoch(s['endedAt'] as int),
        phases: [
          for (final p in s['phases'] as List) PhasePoint.fromJson((p as Map).cast<String, dynamic>())
        ],
        snoreEvents: s['snoreEvents'] as int,
        snorePercent: (s['snorePercent'] as num).toDouble(),
        sleepScore: s['sleepScore'] as int,
      ),
      mood: j['mood'] as int?,
      notes: {for (final n in j['notes'] as List) n as String},
      steps: j['steps'] as int?,
      weatherF: j['weatherF'] as int?,
      snoreMinutes: j['snoreMinutes'] as int,
      coughs: j['coughs'] as int,
      breathingPerHour: (j['breathingPerHour'] as num).toDouble(),
      regularity: j['regularity'] as int,
    );
  }

  /// Build a night from a finished tracking run, filling the mocked extras.
  /// [snoreMinutes] / [coughs] from real sensing; omitted for simulated runs,
  /// which get plausible mocked extras.
  factory Night.fromResult(TrackingResult r, {int? seed, int? snoreMinutes, int? coughs, bool real = false}) {
    final rng = math.Random(seed ?? r.session.startedAt.millisecondsSinceEpoch);
    return Night(
      session: r.session,
      steps: real ? null : 3000 + rng.nextInt(9000),
      weatherF: real ? null : 45 + rng.nextInt(25),
      snoreMinutes: snoreMinutes ?? rng.nextInt(25),
      coughs: coughs ?? rng.nextInt(4),
      breathingPerHour: 5 + rng.nextDouble() * 15,
      regularity: 70 + rng.nextInt(30),
    );
  }

  /// A synthetic but plausible night (90-minute cycles, deep sleep early, REM
  /// late, brief wakes) built without the sensor pipeline. Used for the demo
  /// content behind the empty states and for "Load sample nights".
  factory Night.sample(DateTime wokeUp, int seed) {
    final rng = math.Random(seed);
    final hours = 6.5 + rng.nextDouble() * 2.2;
    final epochs = (hours * 120).round();
    final labels = <String>[];
    final onset = 10 + rng.nextInt(30);
    final restless = 0.002 + rng.nextDouble() * 0.04; // per-night chance of a brief wake
    final deepEnd = 0.2 + rng.nextDouble() * 0.25; // how much deep sleep this night gets
    final remStart = 0.8 + rng.nextDouble() * 0.12;
    for (var i = 0; i < epochs; i++) {
      final frac = i / epochs;
      final pos = (i % 180) / 180; // 90-min cycle, 30-s epochs
      final cycle = i ~/ 180;
      String s;
      if (i < onset || frac > 0.985) {
        s = 'awake';
      } else if (rng.nextDouble() < restless) {
        s = 'awake';
      } else if (pos > 0.12 && pos < deepEnd && cycle < 3) {
        s = 'deep';
      } else if (pos > remStart - 0.05 * cycle) {
        s = 'rem';
      } else {
        s = 'light';
      }
      labels.add(s);
    }
    final end = wokeUp;
    final start = end.subtract(Duration(seconds: 30 * epochs));
    final session = SleepSession(
      startedAt: start,
      endedAt: end,
      phases: [for (var i = 0; i < labels.length; i++) PhasePoint(i, labels[i])],
      snoreEvents: rng.nextInt(30),
      snorePercent: rng.nextDouble() * 8,
      sleepScore: SleepTracker.scoreFor(labels),
    );
    return Night(
      session: session,
      mood: rng.nextInt(3),
      steps: 3000 + rng.nextInt(10000),
      weatherF: 45 + rng.nextInt(25),
      snoreMinutes: rng.nextInt(25),
      coughs: rng.nextInt(4),
      breathingPerHour: 5 + rng.nextDouble() * 15,
      regularity: 60 + rng.nextInt(40),
    );
  }
}
