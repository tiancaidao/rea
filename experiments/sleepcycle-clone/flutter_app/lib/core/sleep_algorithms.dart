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

List<String> estimateStages(
  List<EpochFeatures> epochs, {
  int smoothRadius = 5,
  double smoothSigma = 2.0,
  int tailAwakeEpochs = 6,
}) {
  if (epochs.isEmpty) return [];
  final raw = epochs.map((e) => 3.0 * math.min(math.max(e.movement, 0.0), 1.0)).toList();
  for (var i = 0; i < epochs.length; i++) {
    final e = epochs[i];
    if (e.breathingRate != null && e.breathingConf > 0.3) {
      raw[i] = math.max(0.0, raw[i] - 0.3);
    }
  }
  final depth = _smooth(raw, smoothRadius, smoothSigma);
  final labels = depth.map((d) {
    final level = d.clamp(0.0, 3.0).round();
    return stages[level];
  }).toList();
  for (var i = math.max(0, labels.length - tailAwakeEpochs); i < labels.length; i++) {
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

List<SnoreEvent> detectSnoreEvents(
  List<double> frameProbs, {
  double onThreshold = 0.5,
  int majorityWindow = 3,
  int minEventFrames = 3,
  double minMeanProb = 0.5,
}) {
  final n = frameProbs.length;
  if (n == 0) return [];
  final half = majorityWindow ~/ 2;
  final on = <bool>[];
  for (var i = 0; i < n; i++) {
    var votes = 0, total = 0;
    for (var j = i - half; j <= i + half; j++) {
      if (j >= 0 && j < n) {
        total++;
        if (frameProbs[j] >= onThreshold) votes++;
      }
    }
    on.add(votes * 2 > total);
  }
  final events = <SnoreEvent>[];
  int? start;
  for (var i = 0; i <= n; i++) {
    final active = i < n ? on[i] : false;
    if (active && start == null) {
      start = i;
    } else if (!active && start != null) {
      final seg = frameProbs.sublist(start, i);
      final meanP = seg.reduce((a, b) => a + b) / seg.length;
      if ((i - start) >= minEventFrames && meanP >= minMeanProb) {
        events.add(SnoreEvent(start, i, meanP));
      }
      start = null;
    }
  }
  return events;
}
