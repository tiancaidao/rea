// Original, portable sleep-tracking algorithms — a Dart port of sleep_core/.
// Clean-room, our own parameters; not copied from any app. ML stages are
// pluggable: you feed in scores/embeddings from your own trained models.

import 'dart:math' as math;

const double gravity = 9.80665;

// ---------------------------------------------------------------------------
// Movement detection
// ---------------------------------------------------------------------------

class MovementConfig {
  final int sampleHz;
  final int epochSeconds;
  double spikeThresholdG;
  MovementConfig({this.sampleHz = 50, this.epochSeconds = 30, this.spikeThresholdG = 0.03});
  int get samplesPerEpoch => sampleHz * epochSeconds;
}

/// Streams accelerometer samples and emits one movement value per epoch.
class MovementAggregator {
  final MovementConfig config;
  double? _prevMag;
  int _epochSamples = 0;
  int _epochSpikes = 0;
  double _epochEnergy = 0;
  int _epochIndex = 0;

  MovementAggregator(this.config);

  /// Feed one raw sample (m/s^2). Returns movement amount when an epoch
  /// completes, else null.
  double? addSample(double x, double y, double z) {
    final magG = math.sqrt(x * x + y * y + z * z) / gravity;
    if (_prevMag != null) {
      final delta = (magG - _prevMag!).abs();
      _epochEnergy += delta;
      if (delta > config.spikeThresholdG) _epochSpikes++;
    }
    _prevMag = magG;
    _epochSamples++;
    if (_epochSamples >= config.samplesPerEpoch) {
      final amount = _epochSpikes + _epochEnergy;
      _epochIndex++;
      _epochSamples = 0;
      _epochSpikes = 0;
      _epochEnergy = 0;
      return amount;
    }
    return null;
  }

  int get epochsEmitted => _epochIndex;
}

double calibrateThreshold(List<double> quietWindowG, {double safety = 1.5}) {
  if (quietWindowG.length < 2) return MovementConfig().spikeThresholdG;
  final deltas = <double>[];
  for (var i = 1; i < quietWindowG.length; i++) {
    deltas.add((quietWindowG[i] - quietWindowG[i - 1]).abs());
  }
  deltas.sort();
  final median = deltas[deltas.length ~/ 2];
  return math.max(median * safety, 0.005);
}

// ---------------------------------------------------------------------------
// Sleep staging
// ---------------------------------------------------------------------------

const List<String> stages = ['deep', 'light', 'rem', 'awake']; // index = depth 0..3

class EpochFeatures {
  final double movement; // normalized 0..1
  final double? breathingRate;
  final double breathingConf;
  EpochFeatures(this.movement, {this.breathingRate, this.breathingConf = 0});
}

List<double> _gaussianKernel(int radius, double sigma) {
  final ks = <double>[];
  for (var i = -radius; i <= radius; i++) {
    ks.add(math.exp(-(i * i) / (2 * sigma * sigma)));
  }
  final s = ks.reduce((a, b) => a + b);
  return ks.map((k) => k / s).toList();
}

List<double> _smooth(List<double> xs, int radius, double sigma) {
  if (xs.isEmpty) return xs;
  final k = _gaussianKernel(radius, sigma);
  final out = <double>[];
  for (var i = 0; i < xs.length; i++) {
    var acc = 0.0;
    for (var j = 0; j < k.length; j++) {
      final idx = math.min(math.max(i + j - radius, 0), xs.length - 1);
      acc += xs[idx] * k[j];
    }
    out.add(acc);
  }
  return out;
}

double _bell(double x, double mu, double sigma) =>
    math.exp(-((x - mu) * (x - mu)) / (2 * sigma * sigma));

/// Estimate 4-stage sleep from per-epoch movement.
///
/// Movement alone can tell *asleep vs awake* but cannot by itself separate
/// deep from REM (both are quiet). So, like actigraphy-based stagers, we add a
/// transparent population prior over sleep architecture: nights run in ~90 min
/// cycles, deep sleep dominates the early cycles, and REM grows toward morning
/// and clusters at the end of each cycle. Movement then pushes an epoch lighter
/// or marks it awake. This is our own heuristic — swap in a trained model
/// (lib via ONNX/TFLite) for real staging; the contract (per-epoch features ->
/// labels) is the same.
List<String> estimateStages(
  List<EpochFeatures> epochs, {
  int epochSeconds = 30,
  int smoothRadius = 3,
  double smoothSigma = 1.5,
  double wakeThreshold = 0.55,
  int onsetEpochs = 6,
  int tailAwakeEpochs = 4,
}) {
  if (epochs.isEmpty) return [];
  final n = epochs.length;
  final mv = _smooth(
    epochs.map((e) => math.min(math.max(e.movement, 0.0), 1.0)).toList(),
    smoothRadius,
    smoothSigma,
  );
  final cycleEpochs = (90 * 60) ~/ epochSeconds; // ~90 min
  final labels = List<String>.filled(n, 'light');
  for (var i = 0; i < n; i++) {
    final m = mv[i];
    if (m > wakeThreshold) {
      labels[i] = 'awake';
      continue;
    }
    final cycleIdx = i / cycleEpochs; // 0,1,2...
    final pos = (i % cycleEpochs) / cycleEpochs; // 0..1 within the cycle
    // breathing, when available, nudges toward deeper sleep
    final e = epochs[i];
    final breathBonus =
        (e.breathingRate != null && e.breathingConf > 0.3) ? 0.15 : 0.0;
    final deepScore =
        math.max(0.0, 1.0 - cycleIdx * 0.45) * _bell(pos, 0.3, 0.18) +
            breathBonus -
            m; // movement suppresses deep
    final remScore =
        (0.15 + cycleIdx * 0.28).clamp(0.0, 1.0) * _bell(pos, 0.85, 0.12);
    final lightScore = 0.35 + 0.5 * m;
    if (deepScore >= remScore && deepScore >= lightScore && m < 0.25) {
      labels[i] = 'deep';
    } else if (remScore > lightScore && remScore >= deepScore) {
      labels[i] = 'rem';
    } else {
      labels[i] = 'light';
    }
  }
  // sleep onset is light/awake; the last stretch is waking up
  for (var i = 0; i < math.min(onsetEpochs, n); i++) {
    if (labels[i] == 'deep' || labels[i] == 'rem') labels[i] = 'light';
  }
  for (var i = math.max(0, n - tailAwakeEpochs); i < n; i++) {
    labels[i] = 'awake';
  }
  return labels;
}

// ---------------------------------------------------------------------------
// Smart alarm
// ---------------------------------------------------------------------------

double _percentile(List<double> sortedXs, double p) {
  if (sortedXs.isEmpty) return 0;
  final k = (sortedXs.length - 1) * p;
  final lo = k.floor();
  final hi = math.min(lo + 1, sortedXs.length - 1);
  return sortedXs[lo] + (sortedXs[hi] - sortedXs[lo]) * (k - lo);
}

class SmartAlarm {
  final int windowMinutes;
  final double highPercentile;
  final double lowPercentile;
  SmartAlarm({this.windowMinutes = 30, this.highPercentile = 0.90, this.lowPercentile = 0.50});

  bool shouldFire(int minuteInWindow, double recentMovement, List<double> nightMovement) {
    if (minuteInWindow >= windowMinutes) return true;
    final xs = [...nightMovement]..sort();
    final high = _percentile(xs, highPercentile);
    final low = _percentile(xs, lowPercentile);
    final frac = minuteInWindow / math.max(windowMinutes, 1);
    final threshold = high + (low - high) * frac;
    return recentMovement >= threshold;
  }
}

// ---------------------------------------------------------------------------
// Snore event post-processing
// ---------------------------------------------------------------------------

class SnoreEvent {
  final int startFrame;
  final int endFrame; // exclusive
  final double meanProb;
  SnoreEvent(this.startFrame, this.endFrame, this.meanProb);
}

/// Group per-frame probabilities into events: majority vote over
/// [majorityWindow] frames, then keep runs of at least [minEventFrames] whose
/// mean probability is at least [minMeanProb].
///
/// A NaN frame abstains (the live tracker marks quiet, gated seconds this way):
/// it doesn't vote, and a run of up to [maxGap] NaN frames between two active
/// frames is bridged — the silent breath between two snores belongs to the same
/// snoring episode.
List<SnoreEvent> detectSnoreEvents(
  List<double> frameProbs, {
  double onThreshold = 0.5,
  int majorityWindow = 3,
  int minEventFrames = 3,
  double minMeanProb = 0.5,
  int maxGap = 0,
}) {
  final n = frameProbs.length;
  if (n == 0) return [];
  final half = majorityWindow ~/ 2;
  final on = <bool>[];
  for (var i = 0; i < n; i++) {
    var votes = 0, total = 0;
    for (var j = i - half; j <= i + half; j++) {
      if (j >= 0 && j < n && !frameProbs[j].isNaN) {
        total++;
        if (frameProbs[j] >= onThreshold) votes++;
      }
    }
    on.add(!frameProbs[i].isNaN && votes * 2 > total);
  }
  if (maxGap > 0) {
    var i = 0;
    while (i < n) {
      if (frameProbs[i].isNaN) {
        var j = i;
        while (j < n && frameProbs[j].isNaN) {
          j++;
        }
        if (i > 0 && j < n && on[i - 1] && on[j] && j - i <= maxGap) {
          for (var k = i; k < j; k++) {
            on[k] = true;
          }
        }
        i = j;
      } else {
        i++;
      }
    }
  }
  final events = <SnoreEvent>[];
  int? start;
  for (var i = 0; i <= n; i++) {
    final active = i < n ? on[i] : false;
    if (active && start == null) {
      start = i;
    } else if (!active && start != null) {
      final seg = frameProbs.sublist(start, i).where((p) => !p.isNaN).toList();
      final meanP = seg.isEmpty ? 0.0 : seg.reduce((a, b) => a + b) / seg.length;
      if ((i - start) >= minEventFrames && meanP >= minMeanProb) {
        events.add(SnoreEvent(start, i, meanP));
      }
      start = null;
    }
  }
  return events;
}
