import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sleep_tracker/sensing/live_tracker.dart';
import 'package:sleep_tracker/sensing/stage_model.dart';

/// On-device check of the trained stager, run on an emulator or phone:
///
///   flutter test integration_test/stage_on_device_test.dart --dart-define=STAGE_MODEL=true
///
/// Needs assets/models/stage_tcn.json from ml/training/train_stage.py (gitignored).
/// It carries a held-out test night (phone-like rendering) and PyTorch's output for
/// it (Viterbi-decoded stages). The night is replayed epoch by epoch through LiveTracker, the path a real
/// night takes, and the staging it produces is compared with PyTorch.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stager: bundled, runs on device, matches PyTorch on a held-out night', (_) async {
    expect(stageModelFlag, isTrue, reason: 'run with --dart-define=STAGE_MODEL=true');
    final model = await StageModel.load();
    expect(model, isNotNull, reason: 'assets/models/stage_tcn.json not bundled');
    final j = jsonDecode(await rootBundle.loadString('assets/models/stage_tcn.json'));
    final raw = [for (final v in j['parity']['raw'] as List) (v as num).toDouble()];
    final want = [for (final s in j['parity']['stages'] as List) StageModel.labels[s as int]];

    final t = LiveTracker(useMicrophone: false, useStageModel: true)..stageModel = model;
    for (final r in raw) {
      t.addAccelEpoch(r);
    }
    final sw = Stopwatch()..start();
    final phases = t.analyze().session.phases.map((p) => p.phase).toList();
    final ms = sw.elapsedMilliseconds;
    final agree = [for (var i = 0; i < raw.length; i++) phases[i] == want[i]].where((x) => x).length;
    final counts = {for (final l in StageModel.labels) l: phases.where((p) => p == l).length};
    debugPrint('STAGE_SELFTEST ${raw.length} epochs (${(raw.length / 120).toStringAsFixed(1)} h) staged in $ms ms; '
        'agreement with PyTorch $agree/${raw.length}; stages $counts');
    expect(agree, raw.length);
    expect(ms, lessThan(2000));
  });
}
