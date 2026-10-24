import 'dart:io';
import 'dart:typed_data';

import 'package:duplicates_cleaner/core/xxhash32.dart';
import 'package:duplicates_cleaner/services/content_fingerprint.dart';
import 'package:duplicates_cleaner/services/image_hash.dart';
import 'package:duplicates_cleaner/services/image_similarity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image scene(int w, int h, {int shift = 0}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x * 256 ~/ w, v = y * 256 ~/ h;
      final d = (u - 90) * (u - 90) + (v - 140) * (v - 140) < 3600;
      im.setPixelRgb(
        x,
        y,
        (d ? 240 : u) + shift,
        (d ? 40 : v) + shift,
        d ? 30 : 128,
      );
    }
  }
  return im;
}

ImageFeatures features(
  int height, {
  int pHash = 0,
  (int, int, int) crop = (128, 128, 128),
  int region = 100,
}) => ImageFeatures(
  height: height,
  tl: region,
  tr: region,
  centreAvg: region,
  bl: region,
  br: region,
  centreDelta: 100,
  archSpiroDelta: 50,
  pHash: pHash,
  cropDelta: crop,
);

void main() {
  test('.NET rounding is half to even', () {
    expect([0.5, 1.5, 2.5, -0.5, 2.4, 2.6].map(roundHalfEven), [
      0,
      2,
      2,
      0,
      2,
      3,
    ]);
  });

  test('gray copy is 100 px wide and its height tracks aspect ratio', () {
    expect(GrayImage.fromImage(scene(400, 300)).height, 75);
    expect(GrayImage.fromImage(scene(300, 300)).height, 100);
    expect(GrayImage.fromImage(scene(1000, 3)).height, 1);
  });

  test('pHash never sets the DC bit and survives a resize', () {
    final a = ImageFeatures.of(scene(400, 400));
    final b = ImageFeatures.of(scene(240, 240));
    expect(a.pHash & 1, 0);
    expect(hammingDistance(a.pHash, b.pHash), lessThanOrEqualTo(5));
  });

  test('spiral points stay in bounds and never repeat consecutively', () {
    final pts = archSpiroPoints(GrayImage.fromImage(scene(400, 300)));
    expect(pts, isNotEmpty);
    for (var i = 1; i < pts.length; i++) {
      expect(pts[i] != pts[i - 1], isTrue);
    }
    expect(
      pts.every((p) => p.$1 >= 0 && p.$1 < 100 && p.$2 >= 0 && p.$2 < 75),
      isTrue,
    );
  });

  test('orthonormal DCT keeps energy', () {
    final v = [1.0, 5.0, 3.0, 8.0, 2.0];
    final c = dct1d(v);
    double e(List<double> l) => l.fold(0.0, (s, x) => s + x * x);
    expect(e(c), closeTo(e(v), 1e-9));
  });

  test('pass 1: all checks, or pHash within 5 alone', () {
    expect(
      firstPassMatch(features(100, pHash: 0), features(100, pHash: 0xFFF)),
      isTrue,
    );
    expect(
      firstPassMatch(features(100, pHash: 0), features(100, pHash: 0x1FFF)),
      isFalse,
    );
    expect(
      firstPassMatch(
        features(100, region: 100),
        features(100, pHash: 0x1F, region: 200),
      ),
      isTrue,
    );
    expect(
      firstPassMatch(
        features(100, region: 100),
        features(100, pHash: 0x3F, region: 200),
      ),
      isFalse,
    );
  });

  test('only equal heights are compared, and pass 2 rescues close colours', () {
    final items = [
      features(100, pHash: 0),
      features(75, pHash: 0), // other aspect ratio: never compared
      features(100, pHash: 0x1FFF, region: 200), // 13 bits: fails pass 1
      features(60, pHash: 0, crop: (200, 50, 50)),
      features(
        60,
        pHash: 0x1FFF,
        crop: (201, 50, 50),
        region: 200,
      ), // alone in its bucket for pass 2
      features(
        60,
        pHash: 0,
        crop: (50, 50, 200),
        region: 0,
      ), // pHash 0 apart: pass 1
    ];
    // Pass 1 groups come first; pass 2 then links 0 and 2 (same centre colour,
    // pHash 13 apart). Item 4 is the only pass 1 singleton of height 60.
    final progress = <int>[];
    expect(groupSimilarImages(items, onProgress: progress.add), [
      [3, 5],
      [0, 2],
    ]);
    expect(progress, isNotEmpty);
    expect(progress.last, 100);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('chroma distance ignores lightness', () {
    expect(cropChromaDelta((100, 100, 100), (200, 200, 200)), lessThan(0.01));
    expect(cropChromaDelta((200, 50, 50), (50, 50, 200)), greaterThan(50));
  });

  test('content hash matches the original formula', () async {
    final dir = Directory.systemTemp.createTempSync('dc_hash');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i * 31 & 0xFF));
    final f = File('${dir.path}/a.bin')..writeAsBytesSync(bytes);
    final first = Uint8List(4096)..setRange(0, 2952, bytes, 2048);
    final last = Uint8List.sublistView(bytes, 5000 - 2048);
    expect(
      await originalContentHash(f),
      2 * XxHash32.hash(first) + 5000 + XxHash32.hash(last),
    );
    final tiny = File('${dir.path}/b.bin')..writeAsBytesSync([1, 2, 3]);
    expect(await originalContentHash(tiny), 0);
  });
}
