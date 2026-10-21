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
    for (var epoch = 0; epoch < totalEpochs; epoch++) {
      // restless near sleep onset, a mid-night stir, and before wake
      final frac = epoch / totalEpochs;
      final restless = frac < 0.06 || frac > 0.95 || (0.45 < frac && frac < 0.48);
      final amp = restless ? 0.5 : 0.04;
      for (var i = 0; i < sampleHz * 30; i++) {
        final moving = rng.nextDouble() < (restless ? 0.06 : 0.005);
        final a = moving ? amp : 0.01;
        yield [
          _g(rng, a),
          _g(rng, a),
          gravity + _g(rng, a),
        ];
      }
    }
  }

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
    // simple, transparent score: reward deep+rem, penalize wake
    final s = 100 * (0.5 + 0.9 * deep + 0.6 * rem - 0.8 * awake);
    return s.clamp(0, 100).round();
  }
}
