// Orchestrates a night of tracking: raw accelerometer samples -> per-epoch
// movement -> sleep stages -> a SleepSession. Snore scoring plugs in where your
// own sound model's frame probabilities would arrive.
//
// Real sensing is native (CoreMotion / SensorManager + a background audio
// service) and arrives via a platform channel. For development and for the
// "how close is it" demo, SimulatedNight produces a realistic sample stream so
// the whole pipeline runs with no device.

import 'dart:math' as math;
import '../core/sleep_algorithms.dart';
import '../data/models.dart';

/// A source of accelerometer samples (m/s^2). Back it with a platform channel
/// for real sensing, or with SimulatedNight for development.
abstract class AccelerometerSource {
  /// Called with (x, y, z) at roughly [MovementConfig.sampleHz].
  Stream<List<double>> samples();
}

class SimulatedNight implements AccelerometerSource {
  final int hours;
  final int sampleHz;
  final int seed;
  SimulatedNight({this.hours = 8, this.sampleHz = 50, this.seed = 42});

  @override
  Stream<List<double>> samples() async* {
    final rng = math.Random(seed);
    final totalEpochs = hours * 60 * 60 ~/ 30;
    const cycleEpochs = (90 * 60) ~/ 30; // ~90 min
    // each night gets its own restlessness so scores vary seed-to-seed
    final nightRestlessness = 0.3 + rng.nextDouble() * 1.9;
    for (var epoch = 0; epoch < totalEpochs; epoch++) {
      final frac = epoch / totalEpochs;
      final pos = (epoch % cycleEpochs) / cycleEpochs; // within cycle
      // light sleep (more micro-movement) peaks at cycle ends; nights get
      // lighter toward morning; sleep onset and pre-wake are restless.
      final lightness = _bell(pos, 0.9, 0.15) + 0.4 * _bell(pos, 0.5, 0.3) + 0.5 * frac;
      final onsetOrWake = frac < 0.05 || frac > 0.96;
      // occasional brief awakening
      final stir = rng.nextDouble() < 0.03 * nightRestlessness;
      final amp = onsetOrWake || stir ? 0.45 : (0.02 + 0.12 * lightness * nightRestlessness);
      final moveProb = onsetOrWake || stir ? 0.06 : 0.004 + 0.02 * lightness;
      for (var i = 0; i < sampleHz * 30; i++) {
        final a = rng.nextDouble() < moveProb ? amp : 0.01;
        yield [
          _g(rng, a),
          _g(rng, a),
          gravity + _g(rng, a),
        ];
      }
    }
  }

  double _bell(double x, double mu, double sigma) =>
      math.exp(-((x - mu) * (x - mu)) / (2 * sigma * sigma));

  double _g(math.Random rng, double sd) => (rng.nextDouble() - 0.5) * 2 * sd;
}

class TrackingResult {
  final SleepSession session;
  final List<double> epochMovement; // normalized 0..1 per epoch
  TrackingResult(this.session, this.epochMovement);
}

class SleepTracker {
  final MovementConfig config;
  SleepTracker({MovementConfig? config}) : config = config ?? MovementConfig();

  /// Consume a full night from [source] and build a session. Returns when the
  /// stream completes. For SimulatedNight this is near-instant.
  Future<TrackingResult> run(
    AccelerometerSource source, {
    DateTime? startedAt,
    List<double>? snoreFrameProbs, // optional: from your own sound model
  }) async {
    final start = startedAt ?? DateTime.now();
    final agg = MovementAggregator(config);
    final movements = <double>[];
    await for (final s in source.samples()) {
      final m = agg.addSample(s[0], s[1], s[2]);
      if (m != null) movements.add(m);
    }
    final maxM = movements.isEmpty ? 1.0 : movements.reduce(math.max);
    final norm = movements.map((m) => maxM == 0 ? 0.0 : m / maxM).toList();
    final feats = norm.map((m) => EpochFeatures(m)).toList();
    final labels = estimateStages(feats);
    final phases = <PhasePoint>[
      for (var i = 0; i < labels.length; i++) PhasePoint(i, labels[i])
    ];

    final snoreEvents =
        snoreFrameProbs == null ? 0 : detectSnoreEvents(snoreFrameProbs).length;
    final asleepEpochs = labels.where((l) => l != 'awake').length;
    final snorePercent = asleepEpochs == 0 || snoreFrameProbs == null
        ? 0.0
        : 100.0 * snoreEvents / asleepEpochs;

    final session = SleepSession(
      startedAt: start,
      endedAt: start.add(Duration(seconds: 30 * labels.length)),
      phases: phases,
      snoreEvents: snoreEvents,
      snorePercent: snorePercent,
      sleepScore: _score(labels),
    );
    return TrackingResult(session, norm);
  }

  int _score(List<String> labels) {
    if (labels.isEmpty) return 0;
    final total = labels.length;
    final deep = labels.where((l) => l == 'deep').length / total;
    final rem = labels.where((l) => l == 'rem').length / total;
    final awake = labels.where((l) => l == 'awake').length / total;
    final efficiency = 1.0 - awake; // share of the night actually asleep
    // Transparent score: mostly sleep efficiency, plus credit for hitting
    // healthy deep (~18%) and REM (~22%) proportions. Won't peg at 100.
    final deepTerm = (deep / 0.18).clamp(0.0, 1.0);
    final remTerm = (rem / 0.22).clamp(0.0, 1.0);
    final s = 100 * (0.6 * efficiency + 0.22 * deepTerm + 0.18 * remTerm);
    return s.clamp(0, 100).round();
  }
}
