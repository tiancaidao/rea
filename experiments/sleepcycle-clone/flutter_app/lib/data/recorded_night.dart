import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../core/sleep_algorithms.dart';
import '../sensing/sleep_tracker.dart';
import 'models.dart';
import 'night.dart';

/// A real recorded night used as the source for sample and demo nights.
///
/// In the comparison build this is `assets/data/dummy_sleep_events.csv`, the
/// sample night bundled in the original APK (gitignored, local only). Format:
/// `eventType, timestamp(ns), intensity`. We use type 1 (movement events with
/// an intensity) and 701/702 (snore start/stop). Absent the file, callers fall
/// back to the synthetic [Night.sample].
class RecordedNight {
  final int minutes; // night length
  final List<(double minute, double intensity)> movements;
  final List<(double start, double end)> snores;
  RecordedNight(this.minutes, this.movements, this.snores);

  static RecordedNight? _cached;
  static bool _tried = false;

  static Future<RecordedNight?> load() async {
    if (_tried) return _cached;
    _tried = true;
    try {
      final raw = await rootBundle.loadString('assets/data/dummy_sleep_events.csv');
      _cached = parse(raw);
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }

  static RecordedNight? get cached => _cached;

  static RecordedNight? parse(String csv) {
    final rows = <(int, int, double)>[];
    for (final line in csv.split('\n').skip(1)) {
      final p = line.split(',');
      if (p.length < 3) continue;
      final t = int.tryParse(p[0].trim());
      final ts = int.tryParse(p[1].trim());
      final v = double.tryParse(p[2].trim());
      if (t == null || ts == null || v == null) continue;
      rows.add((t, ts, v));
    }
    if (rows.isEmpty) return null;
    final t0 = rows.map((r) => r.$2).reduce(math.min);
    final t1 = rows.map((r) => r.$2).reduce(math.max);
    double minute(int ts) => (ts - t0) / 6e10;
    final moves = [for (final r in rows) if (r.$1 == 1) (minute(r.$2), r.$3)];
    final starts = [for (final r in rows) if (r.$1 == 701) minute(r.$2)]..sort();
    final ends = [for (final r in rows) if (r.$1 == 702) minute(r.$2)]..sort();
    final snores = <(double, double)>[];
    for (var i = 0; i < math.min(starts.length, ends.length); i++) {
      if (ends[i] > starts[i]) snores.add((starts[i], ends[i]));
    }
    return RecordedNight(minute(t1).ceil(), moves, snores);
  }

  /// Build a Night ending at [wokeUp]. [seed] 0 replays the recording as-is;
  /// other seeds jitter it (stretch, extra restlessness, shifted events) so a
  /// week of sample nights looks like a week, not one night copied.
  Night toNight(DateTime wokeUp, {int seed = 0}) {
    final rng = math.Random(seed);
    final stretch = seed == 0 ? 1.0 : 0.85 + rng.nextDouble() * 0.25;
    final extra = seed == 0 ? 0.0 : rng.nextDouble() * 0.6; // added restlessness
    final mins = (minutes * stretch).round();
    final epochs = mins * 2;
    final mv = List<double>.filled(epochs, 0);
    final maxI = movements.map((m) => m.$2).fold(0.0, math.max);
    for (final m in movements) {
      final e = ((m.$1 * stretch + (seed == 0 ? 0 : rng.nextDouble() * 4 - 2)) * 2).round();
      if (e >= 0 && e < epochs) {
        // each event moves its epoch and, more softly, the neighbours
        final v = (m.$2 / (maxI == 0 ? 1 : maxI)) * 1.6;
        mv[e] += v;
        if (e > 0) mv[e - 1] += v * 0.4;
        if (e + 1 < epochs) mv[e + 1] += v * 0.4;
      }
    }
    if (extra > 0) {
      final bursts = (extra * 12).round();
      for (var b = 0; b < bursts; b++) {
        final at = rng.nextInt(epochs);
        for (var k = 0; k < 6 && at + k < epochs; k++) {
          mv[at + k] += 0.5 + rng.nextDouble();
        }
      }
    }
    final labels = estimateStages([for (final m in mv) EpochFeatures(math.min(m, 1.0))]);
    final start = wokeUp.subtract(Duration(minutes: mins));
    final snoreMin = snores.fold(0.0, (a, s) => a + (s.$2 - s.$1)) * stretch;
    final session = SleepSession(
      startedAt: start,
      endedAt: wokeUp,
      phases: [for (var i = 0; i < labels.length; i++) PhasePoint(i, labels[i])],
      snoreEvents: snores.length,
      snorePercent: 100 * snoreMin / math.max(1, mins),
      sleepScore: SleepTracker.scoreFor(labels),
    );
    return Night(
      session: session,
      mood: seed == 0 ? 2 : rng.nextInt(3),
      steps: 3000 + rng.nextInt(9000),
      weatherF: 45 + rng.nextInt(25),
      snoreMinutes: snoreMin.round(),
      coughs: rng.nextInt(4),
      breathingPerHour: 5 + rng.nextDouble() * 15,
      regularity: 65 + rng.nextInt(35),
    );
  }
}

/// A realistic night for demos and seeding: the recording when available,
/// otherwise the synthetic generator.
Night sampleNight(DateTime wokeUp, int seed) =>
    RecordedNight.cached?.toNight(wokeUp, seed: seed) ?? Night.sample(wokeUp, seed);
