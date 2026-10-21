import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/sleep_algorithms.dart';
import '../data/models.dart';
import '../sensing/sleep_tracker.dart';

/// Real overnight sensing on the phone, while the tracking screen is open.
///
/// * Accelerometer (sensors_plus, ~50 Hz): per 30-s epoch, the summed change
///   in acceleration magnitude plus a count of spikes — movement through the
///   mattress.
/// * Microphone (record, 16 kHz PCM, levels only — no audio is kept): per
///   epoch, the loudest 0.5-s window relative to the room's noise floor.
///   Rustling and turning over register as sound when the phone is on the
///   nightstand; long loud stretches are counted as snoring/sound events.
///
/// Both are normalised to 0..1 and the larger one is the epoch's movement,
/// which feeds the same staging used everywhere else. The screen is kept on
/// (dimmed) so Android doesn't suspend the sensors; a foreground service
/// would allow screen-off tracking and is the next step.
class LiveTracker {
  final bool useMicrophone;
  LiveTracker({required this.useMicrophone});

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
        _recorder = rec;
        final stream = await rec.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ));
        micActive = true;
        _micSub = stream.listen(_onPcm);
      }
    }
    _epochTimer = Timer.periodic(const Duration(seconds: epochSeconds), (_) => _closeEpoch());
  }

  // PCM16 chunk → RMS level in dBFS; keep the loudest per epoch
  final List<int> _buf = [];
  void _onPcm(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _buf.add(data.getInt16(i, Endian.little));
      if (_buf.length >= 8000) {
        var sum = 0.0;
        for (final s in _buf) {
          sum += s * s;
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

  double _noiseFloor() {
    if (_windowDb.isEmpty) return -60;
    final s = [..._windowDb]..sort();
    return s[(s.length * 0.2).floor()]; // 20th percentile ≈ quiet room
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
    await WakelockPlus.disable();
  }

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
    final session = SleepSession(
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: epochSeconds * n)),
      phases: [for (var i = 0; i < n; i++) PhasePoint(i, labels[i])],
      snoreEvents: loudEpochs,
      snorePercent: asleep == 0 ? 0 : 100 * loudEpochs / asleep,
      sleepScore: SleepTracker.scoreFor(labels),
    );
    return TrackingResult(session, movement);
  }

  /// Minutes of loud, sustained sound (a snoring proxy until a sound model is plugged in).
  int get soundMinutes => (_soundEpochs.where((d) => d > 15).length * epochSeconds / 60).round();
}
