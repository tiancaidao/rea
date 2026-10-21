import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/sensing/live_tracker.dart';
import 'package:sleep_tracker/sensing/snore_model.dart';

/// Keep in sync with signal() in ml/training/make_frontend_fixture.py.
Float32List syntheticPcm() {
  const sr = SnoreFrontEnd.sampleRate;
  return Float32List.fromList([
    for (var n = 0; n < SnoreFrontEnd.windowSamples; n++)
      0.3 * math.sin(2 * math.pi * 150 * n / sr) * (0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * n / sr)) +
          0.05 * math.sin(2 * math.pi * 2500 * n / sr) +
          0.01 * ((n * 7919) % 1000 / 1000 - 0.5)
  ]);
}

void main() {
  test('Dart front-end matches the Python training front-end', () {
    final fx = jsonDecode(File('test/fixtures/snore_frontend_parity.json').readAsStringSync());
    final want = [for (final v in fx['logmel'] as List) (v as num).toDouble()];
    final got = SnoreFrontEnd.logMel(syntheticPcm());
    expect(got.length, want.length);
    var maxDiff = 0.0;
    for (var i = 0; i < got.length; i++) {
      maxDiff = math.max(maxDiff, (got[i] - want[i]).abs());
    }
    expect(maxDiff, lessThan(2e-3), reason: 'max |dart - python| = $maxDiff');
  });

  // The trained model is gitignored; these run when train_snore.py has exported it.
  final asset = File('assets/models/snore_cnn.json');
  final skip = asset.existsSync() ? false : 'no trained model (run ml/training/train_snore.py)';

  test('Dart CNN matches PyTorch on the exported parity patches', () {
    final raw = asset.readAsStringSync();
    final model = SnoreModel.fromJson(raw);
    for (final p in jsonDecode(raw)['parity'] as List) {
      final x = Float32List.fromList([for (final v in p['x'] as List) (v as num).toDouble()]);
      final want = [for (final v in p['p'] as List) (v as num).toDouble()];
      final got = model.predict(x);
      for (var k = 0; k < want.length; k++) {
        expect(got[k], closeTo(want[k], 1e-3));
      }
    }
  }, skip: skip);

  test('LiveTracker runs the model once per second and gates silence', () async {
    final model = SnoreModel.fromJson(asset.readAsStringSync());
    final t = LiveTracker(useMicrophone: true, useSnoreModel: true);
    expect(await t.enableModel(model), isTrue);
    // 2 s of near-silence then 6 s of a loud 150 Hz buzz, fed 1 s at a time
    final rng = math.Random(0);
    for (var sec = 0; sec < 8; sec++) {
      final b = ByteData(SnoreFrontEnd.sampleRate * 2);
      for (var n = 0; n < SnoreFrontEnd.sampleRate; n++) {
        final v = sec < 2
            ? (rng.nextDouble() - 0.5) * 20
            : 9000 * math.sin(2 * math.pi * 150 * n / SnoreFrontEnd.sampleRate) + (rng.nextDouble() - 0.5) * 20;
        b.setInt16(n * 2, v.round(), Endian.little);
      }
      t.ingestPcm(b.buffer.asUint8List());
      await t.flush();
    }
    // first decision once ~2.02 s are buffered, then one per second
    expect(t.snoreProbs.length, 6);
    expect(t.modelRuns + t.gatedSeconds, 6);
    expect(t.modelRuns, greaterThan(0));
    for (final p in t.snoreProbs) {
      expect(p.isNaN || (p >= 0 && p <= 1), isTrue); // NaN = gated quiet second
    }
  }, skip: skip);
}
