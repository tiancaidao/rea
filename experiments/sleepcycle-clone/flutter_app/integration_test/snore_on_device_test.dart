import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sleep_tracker/sensing/live_tracker.dart';
import 'package:sleep_tracker/sensing/snore_model.dart';

/// On-device check of the snore model path, run on an emulator or phone:
///
///   flutter test integration_test/snore_on_device_test.dart --dart-define=SNORE_MODEL=true
///
/// Needs the gitignored assets from training: assets/models/snore_cnn.json
/// (train_snore.py), plus the held-out recordings from
/// `prepare_data.py --selftest`, copied in for the run and removed after:
///   cp ../ml/data/selftest/*.wav assets/models/   # ... run ...   rm assets/models/selftest_*.wav
/// The recordings are fed
/// through LiveTracker.ingestPcm — the same path the microphone stream uses —
/// one second at a time, so this exercises the bundled asset, the isolate
/// inference, the silence gate and the event smoothing together.
Future<Uint8List> _wavPcm16(String asset) async {
  final b = (await rootBundle.load(asset)).buffer.asUint8List();
  final d = ByteData.sublistView(b);
  var i = 12;
  while (i + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(i, i + 4));
    final len = d.getUint32(i + 4, Endian.little);
    if (id == 'data') return b.sublist(i + 8, i + 8 + len);
    i += 8 + len + (len & 1);
  }
  throw StateError('no data chunk in $asset');
}

Future<LiveTracker> _run(SnoreModel model, String asset) async {
  final pcm = await _wavPcm16(asset);
  final t = LiveTracker(useMicrophone: true, useSnoreModel: true);
  await t.enableModel(model);
  const chunk = SnoreFrontEnd.sampleRate * 2; // 1 s of PCM16
  for (var o = 0; o < pcm.length; o += chunk) {
    t.ingestPcm(pcm.sublist(o, (o + chunk).clamp(0, pcm.length)));
    await t.flush();
  }
  return t;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('snore model: bundled, runs on device, separates snoring from other sounds', (_) async {
    expect(snoreModelFlag, isTrue, reason: 'run with --dart-define=SNORE_MODEL=true');
    final model = await SnoreModel.load();
    expect(model, isNotNull, reason: 'assets/models/snore_cnn.json not bundled');

    final sw = Stopwatch()..start();
    final snore = await _run(model!, 'assets/models/selftest_snore.wav');
    final msPerRun = sw.elapsedMilliseconds / snore.modelRuns;
    final other = await _run(model, 'assets/models/selftest_other.wav');

    int secs(LiveTracker t) => t.snoreEvents.fold(0, (a, e) => a + e.endFrame - e.startFrame);
    debugPrint('SNORE_SELFTEST snore-file: ${snore.snoreProbs.length} s decided, ${snore.modelRuns} runs, '
        '${snore.gatedSeconds} gated, ${snore.snoreEvents.length} events, ${secs(snore)} s snoring');
    debugPrint('SNORE_SELFTEST other-file: ${other.snoreProbs.length} s decided, ${other.modelRuns} runs, '
        '${other.gatedSeconds} gated, ${other.snoreEvents.length} events, ${secs(other)} s snoring');
    debugPrint('SNORE_SELFTEST ${msPerRun.toStringAsFixed(0)} ms per inference (front-end + CNN, isolate)');

    // pipeline checks; the recall/precision numbers themselves are measured in
    // ml/training/RESULTS.md and printed above for the record
    expect(secs(snore), greaterThan(0), reason: 'no snoring found in held-out snoring');
    expect(secs(other), lessThan(other.snoreProbs.length ~/ 20), reason: 'false snoring on other sounds');
    expect(msPerRun, lessThan(1000), reason: 'cannot keep up with real time');
  });

  // Needs RECORD_AUDIO granted beforehand so no dialog blocks the run:
  //   adb shell pm grant com.example.sleep_tracker android.permission.RECORD_AUDIO
  testWidgets('live microphone at 44.1 kHz feeds the model', (_) async {
    final t = LiveTracker(useMicrophone: true, useSnoreModel: true);
    await t.start();
    await Future<void>.delayed(const Duration(seconds: 6));
    await t.stop();
    debugPrint('SNORE_SELFTEST live mic: micActive=${t.micActive} model=${t.modelActive} '
        '${t.snoreProbs.length} s decided (${t.modelRuns} runs, ${t.gatedSeconds} gated)');
    expect(t.micActive, isTrue);
    expect(t.modelActive, isTrue);
    expect(t.snoreProbs.length, greaterThanOrEqualTo(3)); // ~2 s to fill, then 1/s
  });
}
