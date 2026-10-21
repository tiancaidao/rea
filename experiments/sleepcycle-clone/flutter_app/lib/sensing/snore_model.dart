import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// On-device snore / sound-event classifier, in pure Dart (no native ML runtime).
///
/// Front-end is the contract recovered from the original app, implemented to
/// match `ml/audio_pipeline.py` bit-for-bit in float64 then float32:
/// 44.1 kHz PCM → 2048-pt Hann FFT, hop 1024 → 64 mel bands (energy above
/// 8 kHz dropped) → log(mel + 1e-4) → an 86-frame patch (~2.02 s).
///
/// The network is our own 3-block CNN trained by `ml/training/train_snore.py`
/// on openly-licensed data; its BN-folded weights ship as
/// `assets/models/snore_cnn.json` (gitignored — generate it by training).
/// When the asset is absent, [load] returns null and callers keep the
/// loudness proxy.
class SnoreFrontEnd {
  static const sampleRate = 44100;
  static const fftSize = 2048;
  static const hop = 1024;
  static const nMels = 64;
  static const nFrames = 86;
  static const windowSamples = fftSize + (nFrames - 1) * hop; // 89088
  static const fmaxHz = 8000.0;
  static const logFloor = 1e-4;

  static final Float64List _hann = Float64List.fromList(
      [for (var n = 0; n < fftSize; n++) 0.5 - 0.5 * math.cos(2 * math.pi * n / (fftSize - 1))]);
  static final List<Float64List> _fb = _melFilterbank();
  static final _fft = _Fft(fftSize);

  static List<Float64List> _melFilterbank() {
    double hzToMel(double f) => 2595.0 * math.log(1.0 + f / 700.0) / math.ln10;
    double melToHz(double m) => 700.0 * (math.pow(10.0, m / 2595.0) - 1.0);
    const bins = fftSize ~/ 2 + 1;
    final top = hzToMel(sampleRate / 2.0);
    final edges = [
      for (var i = 0; i < nMels + 2; i++) ((fftSize + 1) * melToHz(top * i / (nMels + 1)) / sampleRate).floor()
    ];
    final fb = List.generate(nMels, (_) => Float64List(bins));
    for (var m = 1; m <= nMels; m++) {
      final l = edges[m - 1], c = edges[m], r = edges[m + 1];
      for (var k = l; k < c; k++) {
        if (c != l) fb[m - 1][k] = (k - l) / (c - l);
      }
      for (var k = c; k < r; k++) {
        if (r != c) fb[m - 1][k] = (r - k) / (r - c);
      }
    }
    for (var k = 0; k < bins; k++) {
      if (k * sampleRate / fftSize > fmaxHz) {
        for (final row in fb) {
          row[k] = 0;
        }
      }
    }
    return fb;
  }

  /// [pcm] holds exactly [windowSamples] samples in -1..1 → patch [frame*nMels + mel].
  static Float32List logMel(Float32List pcm) {
    assert(pcm.length >= windowSamples);
    final out = Float32List(nFrames * nMels);
    final re = Float64List(fftSize), im = Float64List(fftSize);
    // only the mel bands' support below fmax matters; skip the rest of the spectrum
    final maxBin = (fmaxHz * fftSize / sampleRate).floor() + 1;
    final mag = Float64List(maxBin);
    for (var f = 0; f < nFrames; f++) {
      final o = f * hop;
      for (var n = 0; n < fftSize; n++) {
        re[n] = pcm[o + n] * _hann[n];
        im[n] = 0;
      }
      _fft.run(re, im);
      for (var k = 0; k < maxBin; k++) {
        mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      }
      for (var m = 0; m < nMels; m++) {
        final row = _fb[m];
        var s = 0.0;
        for (var k = 0; k < maxBin; k++) {
          s += mag[k] * row[k];
        }
        out[f * nMels + m] = math.log(s + logFloor);
      }
    }
    return out;
  }
}

class _Fft {
  final int n;
  final Int32List _rev;
  final Float64List _cos, _sin;
  _Fft(this.n)
      : _rev = Int32List(n),
        _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2) {
    final bits = (math.log(n) / math.ln2).round();
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        r |= ((i >> b) & 1) << (bits - 1 - b);
      }
      _rev[i] = r;
    }
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / n);
      _sin[i] = math.sin(-2 * math.pi * i / n);
    }
  }

  void run(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i], ti = im[i];
        re[i] = re[j];
        im[i] = im[j];
        re[j] = tr;
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1, step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step], wi = _sin[k * step];
          final a = start + k, b = a + half;
          final xr = re[b] * wr - im[b] * wi, xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}

class _Conv {
  final int cout, cin;
  final Float32List w, b; // w[co][ci][3][3]
  _Conv(this.cout, this.cin, this.w, this.b);
}

class SnoreModel {
  final List<String> labels;
  final double mean, std, snoreThreshold;
  final List<_Conv> _convs;
  final Float32List _linW, _linB;

  SnoreModel._(this.labels, this.mean, this.std, this.snoreThreshold, this._convs, this._linW, this._linB);

  int get snoreIndex => labels.indexOf('snore');
  int get coughIndex => labels.indexOf('cough');

  static Future<SnoreModel?> load({String asset = 'assets/models/snore_cnn.json'}) async {
    try {
      return SnoreModel.fromJson(await rootBundle.loadString(asset));
    } catch (_) {
      return null;
    }
  }

  factory SnoreModel.fromJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    Float32List f32(dynamic xs) => Float32List.fromList([for (final x in xs as List) (x as num).toDouble()]);
    return SnoreModel._(
      [for (final l in j['labels'] as List) l as String],
      (j['mean'] as num).toDouble(),
      (j['std'] as num).toDouble(),
      (j['snore_threshold'] as num).toDouble(),
      [
        for (final c in j['convs'] as List)
          _Conv(c['out'] as int, c['inp'] as int, f32(c['w']), f32(c['b']))
      ],
      f32(j['linear']['w']),
      f32(j['linear']['b']),
    );
  }

  /// Class probabilities for one log-mel patch from [SnoreFrontEnd.logMel].
  List<double> predict(Float32List logMel) {
    var h = SnoreFrontEnd.nFrames, w = SnoreFrontEnd.nMels;
    var x = Float32List(h * w);
    for (var i = 0; i < x.length; i++) {
      x[i] = (logMel[i] - mean) / std;
    }
    for (final c in _convs) {
      final y = _convReluPool(x, h, w, c);
      x = y;
      h ~/= 2;
      w ~/= 2;
    }
    // global average pool over the last feature map, then the linear head
    final ch = _convs.last.cout, hw = h * w;
    final pooled = Float64List(ch);
    for (var c = 0; c < ch; c++) {
      var s = 0.0;
      for (var i = 0; i < hw; i++) {
        s += x[c * hw + i];
      }
      pooled[c] = s / hw;
    }
    final n = _linB.length;
    final logits = List<double>.generate(n, (k) {
      var s = _linB[k].toDouble();
      for (var c = 0; c < ch; c++) {
        s += _linW[k * ch + c] * pooled[c];
      }
      return s;
    });
    final mx = logits.reduce(math.max);
    final e = [for (final l in logits) math.exp(l - mx)];
    final z = e.reduce((a, b) => a + b);
    return [for (final v in e) v / z];
  }

  /// 3x3 conv (pad 1, BN folded in) → ReLU → 2x2 max-pool (floor), CHW layout.
  static Float32List _convReluPool(Float32List x, int h, int w, _Conv c) {
    final conv = Float32List(c.cout * h * w);
    for (var co = 0; co < c.cout; co++) {
      final oBase = co * h * w;
      for (var i = 0; i < h * w; i++) {
        conv[oBase + i] = c.b[co];
      }
      for (var ci = 0; ci < c.cin; ci++) {
        final iBase = ci * h * w, wBase = (co * c.cin + ci) * 9;
        for (var ky = 0; ky < 3; ky++) {
          for (var kx = 0; kx < 3; kx++) {
            final wt = c.w[wBase + ky * 3 + kx];
            if (wt == 0) continue;
            final dy = ky - 1, dx = kx - 1;
            final y0 = dy < 0 ? 1 : 0, y1 = dy > 0 ? h - 1 : h;
            final x0 = dx < 0 ? 1 : 0, x1 = dx > 0 ? w - 1 : w;
            for (var yy = y0; yy < y1; yy++) {
              final orow = oBase + yy * w, irow = iBase + (yy + dy) * w + dx;
              for (var xx = x0; xx < x1; xx++) {
                conv[orow + xx] += wt * x[irow + xx];
              }
            }
          }
        }
      }
    }
    final ph = h ~/ 2, pw = w ~/ 2;
    final out = Float32List(c.cout * ph * pw);
    for (var co = 0; co < c.cout; co++) {
      for (var py = 0; py < ph; py++) {
        for (var px = 0; px < pw; px++) {
          final i = co * h * w + (2 * py) * w + 2 * px;
          final m = math.max(math.max(conv[i], conv[i + 1]), math.max(conv[i + w], conv[i + w + 1]));
          out[(co * ph + py) * pw + px] = m > 0 ? m : 0; // ReLU commutes with max
        }
      }
    }
    return out;
  }
}
