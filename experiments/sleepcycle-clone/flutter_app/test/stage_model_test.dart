import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/sensing/live_tracker.dart';
import 'package:sleep_tracker/sensing/stage_model.dart';

void main() {
  // The trained stager is gitignored; these run when train_stage.py has exported it.
  final asset = File('assets/models/stage_tcn.json');
  final skip = asset.existsSync() ? false : 'no trained stager (run ml/training/train_stage.py)';

  test('Dart stager matches PyTorch on the exported held-out night', () {
    final j = jsonDecode(asset.readAsStringSync());
    final model = StageModel.fromJson(asset.readAsStringSync());
    final raw = [for (final v in j['parity']['raw'] as List) (v as num).toDouble()];
    final want = j['parity']['stage_logits'] as List;
    final (lo, wake) = model.logits(raw);
    expect(lo.length, raw.length);
    var maxDiff = 0.0;
    for (var t = 0; t < raw.length; t++) {
      for (var c = 0; c < 4; c++) {
        final d = (lo[t][c] - (want[t][c] as num)).abs();
        if (d > maxDiff) maxDiff = d;
      }
    }
    expect(maxDiff, lessThan(2e-3), reason: 'max |dart - torch| logit = $maxDiff');
    final wantWake = j['parity']['wake_logit'] as List;
    expect(wake[0], closeTo((wantWake[0] as num).toDouble(), 2e-3));
    // the decoded stages (Viterbi when the model carries transitions) match Python
    final wantStages = [for (final s in j['parity']['stages'] as List) StageModel.labels[s as int]];
    expect(model.stages(raw), wantStages);
  }, skip: skip);

  test('LiveTracker uses the stager for nights it can stage', () {
    final j = jsonDecode(asset.readAsStringSync());
    final raw = [for (final v in j['parity']['raw'] as List) (v as num).toDouble()];
    final t = LiveTracker(useMicrophone: false, useStageModel: true)
      ..stageModel = StageModel.fromJson(asset.readAsStringSync());
    for (final r in raw) {
      t.addAccelEpoch(r);
    }
    final phases = t.analyze().session.phases.map((p) => p.phase).toList();
    expect(phases, t.stageModel!.stages(raw));
    expect(phases.toSet().difference(StageModel.labels.toSet()), isEmpty);
  }, skip: skip);
}
