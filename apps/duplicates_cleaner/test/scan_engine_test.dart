import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:duplicates_cleaner/models/enums.dart';
import 'package:duplicates_cleaner/services/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Uint8List randomBytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dc_test'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String rel, List<int> bytes) =>
      File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  Future<List<List<String>>> scan(ScanAlgorithm a,
      {Set<String> ext = const {'bin', 'jpg', 'png'},
      FileSizeExclusion ex = FileSizeExclusion.none}) async {
    final groups = await ScanEngine(ScanRequest(
      roots: [root.path],
      extensions: ext,
      algorithm: a,
      sizeExclusion: ex,
    )).run();
    return [
      for (final g in groups) [for (final i in g.items) p.relative(i.path, from: root.path)]..sort(),
    ];
  }

  test('same content finds identical files across folders', () async {
    final data = randomBytes(20000, 1);
    write('a/one.bin', data);
    write('b/two.bin', data);
    write('c/other.bin', randomBytes(20000, 2));
    expect(await scan(ScanAlgorithm.sameContent), [
      ['a/one.bin', 'b/two.bin'],
    ]);
  });

  test('same content rejects files that only share the fingerprinted edges', () async {
    final a = randomBytes(30000, 3);
    final b = Uint8List.fromList(a)..[15000] ^= 0xFF; // outside both sampled windows
    write('x.bin', a);
    write('y.bin', b);
    expect(await scan(ScanAlgorithm.sameContent), isEmpty);
  });

  test('files under 8 KB are never scanned', () async {
    write('small1.bin', List.filled(4000, 7));
    write('small2.bin', List.filled(4000, 7));
    expect(await scan(ScanAlgorithm.sameContent), isEmpty);
  });

  test('extension filter and hidden folders are respected', () async {
    final data = randomBytes(10000, 4);
    write('keep1.bin', data);
    write('keep2.bin', data);
    write('skip.txt', data);
    write('.hidden/keep3.bin', data);
    expect(await scan(ScanAlgorithm.sameContent), [
      ['keep1.bin', 'keep2.bin'],
    ]);
  });

  test('same name groups case-insensitively', () async {
    write('a/Photo.bin', randomBytes(9000, 5));
    write('b/photo.bin', randomBytes(12000, 6));
    expect(await scan(ScanAlgorithm.sameName), [
      ['a/Photo.bin', 'b/photo.bin'],
    ]);
    expect(await scan(ScanAlgorithm.sameNameAndSize), isEmpty);
  });

  test('size exclusion drops tiny files', () async {
    final data = randomBytes(20000, 7);
    write('a.bin', data);
    write('b.bin', data);
    expect(await scan(ScanAlgorithm.sameSize, ex: FileSizeExclusion.tiny), isEmpty);
    expect(await scan(ScanAlgorithm.sameSize), hasLength(1));
  });

  test('same appearance groups a re-encoded, resized copy', () async {
    final base = img.Image(width: 256, height: 256);
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        final d = (x - 90) * (x - 90) + (y - 140) * (y - 140) < 3600;
        final t = (x * 7 + y * 13) % 9;
        base.setPixelRgb(x, y, (d ? 240 : x) - t, (d ? 40 : y) + t, d ? 30 : 128);
      }
    }
    final orig = write('orig.png', img.encodePng(base, level: 0));
    expect(orig.lengthSync(), greaterThan(8192), reason: 'must pass the 8 KB floor');
    final copy = write('copy.jpg', img.encodeJpg(img.copyResize(base, width: 200), quality: 95));
    expect(copy.lengthSync(), greaterThan(8192), reason: 'must pass the 8 KB floor');
    final other = img.Image(width: 256, height: 256);
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        final v = ((x ~/ 32) + (y ~/ 32)).isEven ? 255 : 0;
        other.setPixelRgb(x, y, v, v, v);
      }
    }
    write('other.png', img.encodePng(other, level: 0));
    expect(await scan(ScanAlgorithm.sameAppearance), [
      ['copy.jpg', 'orig.png'],
    ]);
  });
}
