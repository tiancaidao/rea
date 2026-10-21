import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// On-device sleep stager, in pure Dart: a small dilated temporal CNN over the
/// night's per-30-s movement numbers (the same `raw` the tracker accumulates:
/// summed |Δ|acceleration|| + spikes > 0.03 g), trained by
/// `ml/training/train_stage.py` on open accelerometer + PSG data. Its weights
/// ship as `assets/models/stage_tcn.json` (gitignored). When absent, [load]
/// returns null and the app keeps the heuristic [estimateStages].
class StageModel {
  static const labels = ['awake', 'light', 'deep', 'rem']; // the app's names, model order
  final int kernel;
  final List<int> dilations;
  final List<_Conv1d> _convs;
  final _Conv1d _stage, _wake;

  StageModel._(this.kernel, this.dilations, this._convs, this._stage, this._wake);

  static Future<StageModel?> load({String asset = 'assets/models/stage_tcn.json'}) async {
    try {
      return StageModel.fromJson(await rootBundle.loadString(asset));
    } catch (_) {
      return null;
    }
  }

  factory StageModel.fromJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    Float32List f32(dynamic xs) => Float32List.fromList([for (final x in xs as List) (x as num).toDouble()]);
    final k = j['kernel'] as int;
    final convs = [
      for (final c in j['convs'] as List) _Conv1d(c['out'] as int, c['inp'] as int, k, f32(c['w']), f32(c['b']))
    ];
    final width = convs.last.cout;
    _Conv1d head(Map<String, dynamic> h) {
      final b = f32(h['b']);
      return _Conv1d(b.length, width, 1, f32(h['w']), b);
    }

    return StageModel._(k, [for (final d in j['dilations'] as List) d as int], convs,
        head(j['stage_head'] as Map<String, dynamic>), head(j['wake_head'] as Map<String, dynamic>));
  }

  /// Per-epoch features, mirroring features() in train_stage.py.
  static List<Float32List> features(List<double> raw, {int epochSeconds = 30}) {
    final n = raw.length;
    final s = [...raw]..sort();
    final p95 = s[(0.95 * (n - 1)).floor()], med = s[(0.5 * (n - 1)).floor()];
    final lastH = (n - 1) * epochSeconds / 3600.0;
    final f = List.generate(4, (_) => Float32List(n));
    for (var i = 0; i < n; i++) {
      final t = i * epochSeconds / 3600.0;
      f[0][i] = math.log(1 + 10 * raw[i] / (p95 + 1e-6));
      f[1][i] = math.log(1 + raw[i] / (med + 1e-6));
      f[2][i] = t / 8.0;
      f[3][i] = (lastH - t) / 8.0;
    }
    return f;
  }

  /// (stage logits [epoch][4], wake logit [epoch]) for a night of movement numbers.
  (List<Float32List>, Float32List) logits(List<double> raw) {
    var h = _convs.first.apply(features(raw), 1, relu: true);
    for (var b = 1; b < _convs.length; b++) {
      final y = _convs[b].apply(h, dilations[b], relu: true);
      for (var c = 0; c < h.length; c++) {
        for (var t = 0; t < h[c].length; t++) {
          h[c][t] += y[c][t];
        }
      }
    }
    final st = _stage.apply(h, 1), wk = _wake.apply(h, 1);
    final n = raw.length;
    return ([for (var t = 0; t < n; t++) Float32List.fromList([for (var c = 0; c < 4; c++) st[c][t]])], wk[0]);
  }

  /// One stage label per epoch, in the app's vocabulary.
  List<String> stages(List<double> raw) {
    final (lo, _) = logits(raw);
    return [
      for (final e in lo)
        labels[[0, 1, 2, 3].reduce((a, b) => e[b] > e[a] ? b : a)]
    ];
  }
}

class _Conv1d {
  final int cout, cin, k;
  final Float32List w, b; // w[co][ci][k]
  _Conv1d(this.cout, this.cin, this.k, this.w, this.b);

  /// 'same' zero-padded dilated 1-D convolution over x[cin][T].
  List<Float32List> apply(List<Float32List> x, int dilation, {bool relu = false}) {
    final n = x.first.length, half = k ~/ 2;
    final out = List.generate(cout, (co) => Float32List(n)..fillRange(0, n, b[co]));
    for (var co = 0; co < cout; co++) {
      final o = out[co];
      for (var ci = 0; ci < cin; ci++) {
        final xi = x[ci];
        for (var j = 0; j < k; j++) {
          final wt = w[(co * cin + ci) * k + j];
          final shift = (j - half) * dilation;
          final t0 = math.max(0, -shift), t1 = math.min(n, n - shift);
          for (var t = t0; t < t1; t++) {
            o[t] += wt * xi[t + shift];
          }
        }
      }
      if (relu) {
        for (var t = 0; t < n; t++) {
          if (o[t] < 0) o[t] = 0;
        }
      }
    }
    return out;
  }
}
