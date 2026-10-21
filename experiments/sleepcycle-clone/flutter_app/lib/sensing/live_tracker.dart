import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/sleep_algorithms.dart';
import '../data/models.dart';
import '../sensing/sleep_tracker.dart';
import 'snore_model.dart';

/// Feature flag for the trained snore model (`--dart-define=SNORE_MODEL=true`).
/// Off, or with no model asset bundled, snore minutes use the loudness proxy.
const snoreModelFlag = bool.fromEnvironment('SNORE_MODEL');

/// Front-end + CNN for one window, off the UI isolate. Top-level so the
/// closure sent to the isolate captures only the model and the samples.
Future<List<double>> _classify(SnoreModel m, Float32List window) =>
    Isolate.run(() => m.predict(SnoreFrontEnd.logMel(window)));

/// Real overnight sensing on the phone, while the tracking screen is open.
///
/// * Accelerometer (sensors_plus, ~50 Hz): per 30-s epoch, the summed change
///   in acceleration magnitude plus a count of spikes — movement through the
///   mattress.
/// * Microphone (record, PCM, nothing is kept): per epoch, the loudest 0.5-s
///   window relative to the room's noise floor. Rustling and turning over
///   register as sound when the phone is on the nightstand.
/// * Snore model (behind [snoreModelFlag]): the mic runs at 44.1 kHz and every
///   second the last ~2 s go through [SnoreFrontEnd] + [SnoreModel] in a
///   background isolate, giving P(snore) / P(cough) per second. Quiet seconds
///   (< 3 dB over the room's quietest moments) skip the model. Snore minutes are the
///   smoothed snore events ([detectSnoreEvents]); without the model, long loud
///   stretches stand in for snoring.
///
/// Movement and sound are normalised to 0..1 and the larger one is the epoch's
/// movement, which feeds the same staging used everywhere else. The screen is
/// kept on (dimmed) so Android doesn't suspend the sensors; a foreground
/// service would allow screen-off tracking and is the next step.
class LiveTracker {
  final bool useMicrophone;
  final bool useSnoreModel;
  LiveTracker({required this.useMicrophone, this.useSnoreModel = snoreModelFlag});

  static const epochSeconds = 30;

  final DateTime startedAt = DateTime.now();
  final List<double> _accelEpochs = [];
  final List<double> _soundEpochs = []; // dB above noise floor
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Uint8List>? _micSub;
  AudioRecorder? _recorder;
  Timer? _epochTimer;

  // current epoch accumulators
  double? _prevMag;
  double _energy = 0;
  int _spikes = 0;
  double _loudestDb = -120;
  final List<double> _windowDb = []; // recent 0.5-s levels for the noise floor
  bool micActive = false;

  // snore model state
  SnoreModel? model;
  int _sampleRate = 16000;
  Float32List? _ring; // circular buffer of the last SnoreFrontEnd.windowSamples samples
  int _ringPos = 0, _ringFill = 0, _sinceInference = 0;
  final List<double> snoreProbs = []; // one per second of audio
  final List<double> coughProbs = [];
  int modelRuns = 0, gatedSeconds = 0;
  Future<void> _queue = Future.value();
  int _queued = 0;

  bool get modelActive => model != null;

  Future<void> start() async {
    await WakelockPlus.enable();
    _accelSub = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 20)).listen((e) {
      final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / gravity;
      if (_prevMag != null) {
        final d = (mag - _prevMag!).abs();
        _energy += d;
        if (d > 0.03) _spikes++;
      }
      _prevMag = mag;
    });
    if (useMicrophone) {
      final rec = AudioRecorder();
      if (await rec.hasPermission()) {
        if (useSnoreModel) await enableModel();
        _recorder = rec;
        final stream = await rec.startStream(RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ));
        micActive = true;
        _micSub = stream.listen(ingestPcm);
      }
    }
    _epochTimer = Timer.periodic(const Duration(seconds: epochSeconds), (_) => _closeEpoch());
  }

  /// Load the bundled model; the mic then has to run at the model's 44.1 kHz.
  Future<bool> enableModel([SnoreModel? m]) async {
    model = m ?? await SnoreModel.load();
    if (model != null) {
      _sampleRate = SnoreFrontEnd.sampleRate;
      _ring = Float32List(SnoreFrontEnd.windowSamples);
      _sinceInference = SnoreFrontEnd.sampleRate - 1; // first decision as soon as the window is full
    }
    return model != null;
  }

  // PCM16 chunk → RMS level in dBFS per 0.5 s (keep the loudest per epoch),
  // and with the model, a 1-s cadence of snore/cough inference.
  final List<int> _buf = [];

  /// Feed little-endian PCM16 mono at the current sample rate (the mic stream;
  /// tests feed recorded audio through the same path).
  void ingestPcm(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final half = _sampleRate ~/ 2;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final s = data.getInt16(i, Endian.little);
      _buf.add(s);
      if (_ring != null) _push(s / 32768.0);
      if (_buf.length >= half) {
        var sum = 0.0;
        for (final v in _buf) {
          sum += v * v;
        }
        final rms = math.sqrt(sum / _buf.length) / 32768.0;
        final db = 20 * math.log(math.max(rms, 1e-6)) / math.ln10;
        _loudestDb = math.max(_loudestDb, db);
        _windowDb.add(db);
        if (_windowDb.length > 1200) _windowDb.removeAt(0); // ~10 min
        _buf.clear();
      }
    }
  }

  void _push(double v) {
    final ring = _ring!;
    ring[_ringPos] = v;
    _ringPos = (_ringPos + 1) % ring.length;
    if (_ringFill < ring.length) _ringFill++;
    if (_ringFill == ring.length && ++_sinceInference >= SnoreFrontEnd.sampleRate) {
      _sinceInference = 0;
      // unroll the circular buffer, oldest sample first
      final window = Float32List(ring.length)
        ..setRange(0, ring.length - _ringPos, ring, _ringPos)
        ..setRange(ring.length - _ringPos, ring.length, ring);
      _schedule(window);
    }
  }

  void _schedule(Float32List window) {
    // gate: a quiet room is "other" without running the CNN (saves battery)
    var sum = 0.0;
    for (final v in window) {
      sum += v * v;
    }
    final db = 10 * math.log(math.max(sum / window.length, 1e-12)) / math.ln10;
    final slot = snoreProbs.length;
    // floor from the quietest 5% of the last ~10 min: during long snoring the
    // 20th-percentile floor used for movement sits at snore level and would
    // gate the snores themselves
    if (db < _noiseFloor(0.05) + 3) {
      gatedSeconds++;
      snoreProbs.add(double.nan); // abstains in the event smoothing
      coughProbs.add(double.nan);
      return;
    }
    snoreProbs.add(0);
    coughProbs.add(0);
    if (_queued >= 4) return; // falling behind real time: drop rather than pile up
    _queued++;
    final m = model!;
    _queue = _queue.then((_) async {
      final p = await _classify(m, window);
      snoreProbs[slot] = p[m.snoreIndex];
      coughProbs[slot] = p[m.coughIndex];
      modelRuns++;
      _queued--;
    });
  }

  /// Wait for queued inferences (tests, and before [analyze] at stop).
  Future<void> flush() => _queue;

  void _closeEpoch() {
    _accelEpochs.add(_spikes + _energy);
    _energy = 0;
    _spikes = 0;
    if (micActive) {
      final floor = _noiseFloor();
      _soundEpochs.add(math.max(0, _loudestDb - floor));
      _loudestDb = -120;
    }
  }

  double _noiseFloor([double percentile = 0.2]) {
    if (_windowDb.isEmpty) return -60;
    final s = [..._windowDb]..sort();
    return s[(s.length * percentile).floor()]; // 20th percentile ≈ quiet room
  }

  Duration get elapsed => DateTime.now().difference(startedAt);
  int get epochs => _accelEpochs.length;

  Future<void> stop() async {
    _epochTimer?.cancel();
    _closeEpoch();
    await _accelSub?.cancel();
    await _micSub?.cancel();
    try {
      await _recorder?.stop();
      await _recorder?.dispose();
    } catch (_) {}
    await flush();
    await WakelockPlus.disable();
  }

  /// Smoothed snore events over the per-second probabilities: 3-s majority
  /// vote at the threshold chosen in training, quiet seconds abstaining and
  /// gaps of up to 5 s inside an episode bridged, events at least 3 s long.
  List<SnoreEvent> get snoreEvents => model == null
      ? const []
      : detectSnoreEvents(snoreProbs,
          onThreshold: model!.snoreThreshold,
          minEventFrames: 3,
          minMeanProb: model!.snoreThreshold,
          maxGap: 5);

  /// Turn the recorded epochs into a session.
  TrackingResult analyze() {
    final n = _accelEpochs.length;
    final maxA = _accelEpochs.fold(0.0, math.max);
    final movement = <double>[];
    var loudEpochs = 0;
    for (var i = 0; i < n; i++) {
      final a = maxA == 0 ? 0.0 : _accelEpochs[i] / maxA;
      // ≥ 25 dB above the room's floor is a clear sound event
      final s = i < _soundEpochs.length ? (_soundEpochs[i] / 25).clamp(0.0, 1.0) : 0.0;
      if (i < _soundEpochs.length && _soundEpochs[i] > 15) loudEpochs++;
      movement.add(math.max(a, s * 0.8));
    }
    final labels = estimateStages([for (final m in movement) EpochFeatures(m)]);
    final asleep = labels.where((l) => l != 'awake').length;
    final events = snoreEvents;
    final session = SleepSession(
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: epochSeconds * n)),
      phases: [for (var i = 0; i < n; i++) PhasePoint(i, labels[i])],
      snoreEvents: modelActive ? events.length : loudEpochs,
      snorePercent: asleep == 0
          ? 0
          : modelActive
              ? 100 * _snoreSeconds(events) / (asleep * epochSeconds)
              : 100 * loudEpochs / asleep,
      sleepScore: SleepTracker.scoreFor(labels),
    );
    return TrackingResult(session, movement);
  }

  static int _snoreSeconds(List<SnoreEvent> events) =>
      events.fold(0, (a, e) => a + (e.endFrame - e.startFrame));

  /// Minutes of snoring: model events when the model runs, otherwise minutes of
  /// loud, sustained sound as a proxy.
  int get soundMinutes => modelActive
      ? (_snoreSeconds(snoreEvents) / 60).round()
      : (_soundEpochs.where((d) => d > 15).length * epochSeconds / 60).round();

  /// Cough events (model only; null when the model isn't running).
  int? get coughs => modelActive
      ? detectSnoreEvents(coughProbs, onThreshold: 0.5, majorityWindow: 1, minEventFrames: 1).length
      : null;
}
