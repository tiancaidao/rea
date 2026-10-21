import 'dart:io';
import 'dart:typed_data';

import '../core/xxhash32.dart';

/// Port of `FileCheck.GetXhash`: 2 * XXH32(4096 bytes from offset 2048) +
/// file size + XXH32(last 2048 bytes), as an unsigned 64-bit sum. A short
/// first read leaves zeros in the buffer, as in the original. Files shorter
/// than 2048 bytes make the original's seek from the end fail, and it then
/// returns 0, so this does too.
Future<int> originalContentHash(File file) async {
  final raf = await file.open();
  try {
    final size = await raf.length();
    if (size < 2048) return 0;
    final first = Uint8List(4096);
    await raf.setPosition(2048);
    await raf.readInto(first);
    final last = Uint8List(2048);
    await raf.setPosition(size - 2048);
    await raf.readInto(last);
    return 2 * XxHash32.hash(first) + size + XxHash32.hash(last);
  } on FileSystemException {
    return 0;
  } finally {
    await raf.close();
  }
}

/// Byte-for-byte comparison used to confirm partial fingerprint matches before
/// anything is offered for deletion. The original app skips this step.
Future<bool> filesHaveSameBytes(File a, File b) async {
  final ra = await a.open();
  final rb = await b.open();
  try {
    if (await ra.length() != await rb.length()) return false;
    const chunk = 1 << 20;
    while (true) {
      final ba = await ra.read(chunk);
      final bb = await rb.read(chunk);
      if (ba.length != bb.length) return false;
      if (ba.isEmpty) return true;
      for (var i = 0; i < ba.length; i++) {
        if (ba[i] != bb[i]) return false;
      }
    }
  } finally {
    await ra.close();
    await rb.close();
  }
}
