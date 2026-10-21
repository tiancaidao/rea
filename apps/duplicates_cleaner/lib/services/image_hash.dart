import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 64-bit perceptual hash (DCT of a 32x32 grayscale thumbnail, top-left 8x8
/// coefficients compared against their median), as in the original
/// `SkiaImageMathOperations.GetPHash`. Returns null if the file can't be decoded.
Future<int?> perceptualHash(File file) async {
  final bytes = await file.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return perceptualHashOf(decoded);
}

int perceptualHashOf(img.Image image) {
  const n = 32, r = 8;
  final small = img.grayscale(img.copyResize(image, width: n, height: n, interpolation: img.Interpolation.average));
  final pixels = List.generate(
    n,
    (y) => List.generate(n, (x) => small.getPixel(x, y).luminance.toDouble()),
  );
  final cos = List.generate(
    n,
    (u) => List.generate(n, (x) => math.cos((2 * x + 1) * u * math.pi / (2 * n))),
  );
  final coeffs = <double>[];
  for (var u = 0; u < r; u++) {
    for (var v = 0; v < r; v++) {
      var sum = 0.0;
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          sum += pixels[y][x] * cos[u][y] * cos[v][x];
        }
      }
      final cu = u == 0 ? math.sqrt(1 / n) : math.sqrt(2 / n);
      final cv = v == 0 ? math.sqrt(1 / n) : math.sqrt(2 / n);
      coeffs.add(cu * cv * sum);
    }
  }
  // Skip the DC term when computing the median, as is conventional for pHash.
  final sorted = coeffs.sublist(1)..sort();
  final median = sorted[sorted.length ~/ 2];
  var hash = 0;
  for (var i = 0; i < 64; i++) {
    if (coeffs[i] > median) hash |= 1 << i;
  }
  return hash;
}

int hammingDistance(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}
