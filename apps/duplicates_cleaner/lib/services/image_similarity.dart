import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_hash.dart';

/// `Math.Round(double)` in .NET rounds half to even. The original rounds every
/// feature this way, so the port does too.
double roundHalfEven(double v) {
  final f = v.floorToDouble();
  final diff = v - f;
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f % 2 == 0 ? f : f + 1;
}

/// An 8-bit grayscale bitmap, the `SKColorType.Gray8` copy the original
/// measures everything on.
class GrayImage {
  GrayImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  int at(int x, int y) => pixels[y * width + x];

  /// `SkiaImageOperations.ConvertToGrayScale`: scale to [targetWidth] wide
  /// (square images become targetWidth x targetWidth), keeping the aspect
  /// ratio, with linear sampling and no mipmaps.
  factory GrayImage.fromImage(img.Image source, {int targetWidth = 100}) {
    final w = targetWidth;
    final h = source.width == source.height
        ? targetWidth
        : math.max(1, roundHalfEven(source.height * (targetWidth / source.width)).toInt());
    final scaled = img.copyResize(source,
        width: w, height: h, interpolation: img.Interpolation.linear);
    return GrayImage(w, h, _toGray(scaled));
  }

  /// Linear resize of a gray image, as `SKBitmap.Resize` with linear sampling.
  GrayImage resized(int w, int h) {
    if (w == width && h == height) return this;
    final rgb = img.Image(width: width, height: height, numChannels: 1);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        rgb.setPixelR(x, y, at(x, y));
      }
    }
    final out = img.copyResize(rgb, width: w, height: h, interpolation: img.Interpolation.linear);
    final px = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        px[y * w + x] = out.getPixel(x, y).r.toInt();
      }
    }
    return GrayImage(w, h, px);
  }

  /// Skia converts to Gray8 with the Rec. 709 luma weights.
  static Uint8List _toGray(img.Image image) {
    final px = Uint8List(image.width * image.height);
    var i = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.rNormalized * 255, g = p.gNormalized * 255, b = p.bNormalized * 255;
        px[i++] = (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
      }
    }
    return px;
  }
}

/// Everything `FilesScanner.ProcessImageSimilarity` stores per image.
class ImageFeatures {
  ImageFeatures({
    required this.height,
    required this.tl,
    required this.tr,
    required this.centreAvg,
    required this.bl,
    required this.br,
    required this.centreDelta,
    required this.archSpiroDelta,
    required this.pHash,
    required this.cropDelta,
  });

  /// Height of the 100 px wide grayscale copy, which works as an aspect-ratio
  /// bucket: only images with equal heights are ever compared.
  final int height;
  final int tl, tr, centreAvg, bl, br;
  final double centreDelta;
  final double archSpiroDelta;
  final int pHash;

  /// Average (r, g, b) of the centre cell of a 3x3 grid on the full image.
  final (int, int, int) cropDelta;

  factory ImageFeatures.of(img.Image image) {
    final crop = cropRectColor(image);
    final gray = GrayImage.fromImage(image);
    final regions = cornerRegionAverages(gray, 10);
    return ImageFeatures(
      height: gray.height,
      tl: regions.$1,
      tr: regions.$2,
      centreAvg: regions.$3,
      bl: regions.$4,
      br: regions.$5,
      centreDelta: mPointDelta(gray),
      archSpiroDelta: archSpiroDeltaOf(gray),
      pHash: grayPHash(gray),
      cropDelta: crop,
    );
  }

  /// Decodes [file] at full resolution, like `SkiaImageIOService.LoadBitmapAsync`.
  /// Returns null when the format can't be decoded.
  static Future<ImageFeatures?> fromFile(File file) async {
    final decoded = img.decodeImage(await file.readAsBytes());
    return decoded == null ? null : ImageFeatures.of(decoded);
  }
}

/// `SkiaImageOperations.GetCropRectColDelta`: integer mean colour of the
/// centre third of the image in both directions.
(int, int, int) cropRectColor(img.Image image) {
  final w = image.width, h = image.height;
  final x0 = w ~/ 3, y0 = h ~/ 3, x1 = 2 * w ~/ 3, y1 = 2 * h ~/ 3;
  final count = (x1 - x0) * (y1 - y0);
  if (count <= 0) return (0, 0, 0);
  var r = 0, g = 0, b = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = image.getPixel(x, y);
      r += (p.rNormalized * 255).round();
      g += (p.gNormalized * 255).round();
      b += (p.bNormalized * 255).round();
    }
  }
  return (r ~/ count, g ~/ count, b ~/ count);
}

/// `SkiaImageMathOperations.GetFiCorRegDeltaPrecision`: rounded mean brightness
/// of a [window] square at the top left, top right, centre, bottom left and
/// bottom right.
(int, int, int, int, int) cornerRegionAverages(GrayImage g, int window) {
  final w = math.min(window, g.width), h = math.min(window, g.height);
  int avg(int x0, int y0) {
    if (w <= 0 || h <= 0) return 0;
    var sum = 0;
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        sum += g.at(x, y);
      }
    }
    return roundHalfEven(sum / (w * h)).toInt();
  }

  final right = math.max(0, g.width - w), bottom = math.max(0, g.height - h);
  return (
    avg(0, 0),
    avg(right, 0),
    avg(math.max(0, (g.width - w) ~/ 2), math.max(0, (g.height - h) ~/ 2)),
    avg(0, bottom),
    avg(right, bottom),
  );
}

/// `GetMpointDelta`: root mean square of the centre 30x30 pixels.
double mPointDelta(GrayImage g) {
  final w = math.min(30, g.width), h = math.min(30, g.height);
  final x0 = math.max(0, math.min(g.width - w, g.width ~/ 2 - w ~/ 2));
  final y0 = math.max(0, math.min(g.height - h, g.height ~/ 2 - h ~/ 2));
  var sum = 0.0;
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      final v = g.at(x, y).toDouble();
      sum += v * v;
    }
  }
  return roundHalfEven(math.sqrt(sum / (w * h)));
}

/// `GetArchSpiroDeltaPoints`: pixels visited by the Archimedean spiral
/// r = a + b * theta from the centre, de-duplicated against the previous point.
List<(int, int)> archSpiroPoints(GrayImage g,
    {double a = 2.0, double b = 2.0, double dTheta = 0.3}) {
  final w = g.width, h = g.height;
  if (w == 0 || h == 0) return const [];
  final cx = w ~/ 2, cy = h ~/ 2, limit = math.max(w, h) * 2;
  final points = <(int, int)>[];
  var lastX = -2147483648, lastY = -2147483648;
  var theta = 0.0;
  double r;
  do {
    r = a + b * theta;
    final x = roundHalfEven(cx + r * math.cos(theta)).toInt();
    final y = roundHalfEven(cy + r * math.sin(theta)).toInt();
    if (x >= 0 && x < w && y >= 0 && y < h && (x != lastX || y != lastY)) {
      points.add((x, y));
      lastX = x;
      lastY = y;
    }
    theta += dTheta;
  } while (r <= limit);
  return points;
}

/// `GetCoeffsDCT1D`: orthonormal DCT-II.
List<double> dct1d(List<double> input) {
  final n = input.length;
  if (n == 0) return const [];
  final c0 = math.sqrt(1 / n), ck = math.sqrt(2 / n);
  return List.generate(n, (k) {
    final step = math.pi / n * k;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += input[i] * math.cos((i + 0.5) * step);
    }
    return (k == 0 ? c0 : ck) * sum;
  });
}

/// `GetArkSPDelta`: root mean square of the DCT of the brightness along the
/// spiral.
double archSpiroDeltaOf(GrayImage g) {
  final values = [for (final (x, y) in archSpiroPoints(g)) g.at(x, y).toDouble()];
  if (values.isEmpty) return 0;
  final coeffs = dct1d(values);
  return roundHalfEven(math.sqrt(coeffs.fold(0.0, (s, c) => s + c * c) / coeffs.length));
}

/// `GetPHash(gray, 32, 8)`: resize to [dctSize] square, take the top-left
/// [reducedSize] block of the 2D DCT, and set a bit for every coefficient above
/// the mean of the non-DC ones. The DC bit is always 0.
int grayPHash(GrayImage gray, {int dctSize = 32, int reducedSize = 8}) {
  final n = dctSize, r = reducedSize;
  final g = gray.resized(n, n);
  final scale = math.pi / (2 * n);
  final cosTable = List.generate(
      n, (u) => List.generate(n, (x) => math.cos((2 * x + 1) * u * scale)));
  final dct = List.generate(n, (_) => List.filled(n, 0.0));
  for (var u = 0; u < n; u++) {
    final cu = u == 0 ? 1 / math.sqrt(n) : math.sqrt(2 / n);
    for (var v = 0; v < n; v++) {
      final cv = v == 0 ? 1 / math.sqrt(n) : math.sqrt(2 / n);
      var sum = 0.0;
      for (var y = 0; y < n; y++) {
        final cy = cosTable[v][y];
        for (var x = 0; x < n; x++) {
          sum += g.at(x, y) * cosTable[u][x] * cy;
        }
      }
      dct[u][v] = cu * cv * sum;
    }
  }
  var total = 0.0;
  var count = 0;
  for (var i = 0; i < r; i++) {
    for (var j = 0; j < r; j++) {
      if (i == 0 && j == 0) continue;
      total += dct[i][j];
      count++;
    }
  }
  final mean = count > 0 ? total / count : 0.0;
  var hash = 0;
  for (var i = 0; i < r; i++) {
    for (var j = 0; j < r; j++) {
      if (i == 0 && j == 0) continue;
      if (dct[i][j] > mean) hash |= 1 << ((i * r + j) & 63);
    }
  }
  return hash;
}

/// `RgbToNormalize`: sRGB to CIE L*a*b* (D65).
(double, double, double) rgbToLab((int, int, int) rgb) {
  double lin(int c) {
    final v = c / 255.0;
    return v > 0.04045 ? math.pow((v + 0.055) / 1.055, 2.4).toDouble() : v / 12.92;
  }

  double fx(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

  final r = lin(rgb.$1), g = lin(rgb.$2), b = lin(rgb.$3);
  final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  final y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.0;
  final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
  final fX = fx(x), fY = fx(y), fZ = fx(z);
  return (116 * fY - 16, 500 * (fX - fY), 200 * (fY - fZ));
}

/// `GetCropChromaDelta`: distance between two centre colours in the a*b*
/// plane, ignoring lightness.
double cropChromaDelta((int, int, int) a, (int, int, int) b) {
  final la = rgbToLab(a), lb = rgbToLab(b);
  final da = la.$2 - lb.$2, db = la.$3 - lb.$3;
  return math.sqrt(da * da + db * db);
}

/// Thresholds used by `FilesScanner`.
class SimilarityThresholds {
  static const pHashLoose = 12;
  static const pHashStrong = 5;
  static const pHashSecondPass = 13;
  static const regionTolerance = 10;
  static const archSpiroTolerance = 5;
  static const chromaTolerance = 2.0;
}

/// Pass 1 test from `GroupByPhaseOne`: all 8 checks pass, or the pHashes are
/// within [SimilarityThresholds.pHashStrong] on their own.
bool firstPassMatch(ImageFeatures a, ImageFeatures b,
    {int regionTolerance = SimilarityThresholds.regionTolerance,
    int spiroTolerance = SimilarityThresholds.archSpiroTolerance}) {
  final distance = hammingDistance(a.pHash, b.pHash);
  var passed = 0;
  if (distance <= SimilarityThresholds.pHashLoose) passed++;
  if ((a.centreAvg - b.centreAvg).abs() <= regionTolerance) passed++;
  if ((a.tl - b.tl).abs() <= regionTolerance) passed++;
  if ((a.tr - b.tr).abs() <= regionTolerance) passed++;
  if ((a.bl - b.bl).abs() <= regionTolerance) passed++;
  if ((a.br - b.br).abs() <= regionTolerance) passed++;
  if ((a.archSpiroDelta - b.archSpiroDelta).abs() <= spiroTolerance) passed++;
  if ((a.centreDelta - b.centreDelta).abs() <= regionTolerance) passed++;
  return passed == 8 || distance <= SimilarityThresholds.pHashStrong;
}

/// Pass 2 test from `GroupFinal`, for images left alone after pass 1.
bool secondPassMatch(ImageFeatures a, ImageFeatures b) =>
    cropChromaDelta(a.cropDelta, b.cropDelta) <= SimilarityThresholds.chromaTolerance &&
    hammingDistance(a.pHash, b.pHash) <= SimilarityThresholds.pHashSecondPass;

/// Breadth-first connected components over [linked], each in input order.
List<List<int>> _components(int n, bool Function(int, int) linked) {
  final adj = List.generate(n, (_) => <int>[]);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (linked(i, j)) {
        adj[i].add(j);
        adj[j].add(i);
      }
    }
  }
  final seen = List.filled(n, false);
  final out = <List<int>>[];
  for (var i = 0; i < n; i++) {
    if (seen[i]) continue;
    seen[i] = true;
    final queue = [i], comp = <int>[];
    while (queue.isNotEmpty) {
      final k = queue.removeAt(0);
      comp.add(k);
      for (final m in adj[k]) {
        if (!seen[m]) {
          seen[m] = true;
          queue.add(m);
        }
      }
    }
    out.add(comp..sort());
  }
  return out;
}

/// `FilesScanner.GroupFinal`: pass 1 inside each height bucket (in order of
/// first appearance), then pass 2 over the pass 1 singletons, bucketed by
/// height in ascending order. Returns groups of indexes into [items]. Unlike
/// the original, groups with a single image are dropped since they hold
/// nothing to delete.
List<List<int>> groupSimilarImages(List<ImageFeatures> items) {
  final buckets = <int, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    buckets.putIfAbsent(items[i].height, () => []).add(i);
  }
  final groups = <List<int>>[];
  final singletons = <int>[];
  for (final bucket in buckets.values) {
    for (final comp in _components(
        bucket.length, (a, b) => firstPassMatch(items[bucket[a]], items[bucket[b]]))) {
      final members = [for (final c in comp) bucket[c]];
      if (members.length == 1) {
        singletons.add(members.first);
      } else {
        groups.add(members);
      }
    }
  }
  final byHeight = <int, List<int>>{};
  for (final s in singletons..sort()) {
    byHeight.putIfAbsent(items[s].height, () => []).add(s);
  }
  final heights = byHeight.keys.toList()..sort();
  for (final h in heights) {
    final bucket = byHeight[h]!;
    if (bucket.length < 2) continue;
    for (final comp in _components(
        bucket.length, (a, b) => secondPassMatch(items[bucket[a]], items[bucket[b]]))) {
      if (comp.length > 1) groups.add([for (final c in comp) bucket[c]]);
    }
  }
  return groups;
}
