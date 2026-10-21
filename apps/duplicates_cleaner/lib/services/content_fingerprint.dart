import 'dart:io';
import 'dart:typed_data';

import '../core/xxhash32.dart';

/// Port of `FileCheck.GetXhash`: the original fingerprints a file by its size,
/// the XXH32 of 4096 bytes starting at offset 2048, and the XXH32 of the last
/// 2048 bytes. Files below 8 KB never reach this point.
Future<String> partialContentFingerprint(File file) async {
  final raf = await file.open();
  try {
    final size = await raf.length();
    final first = Uint8List(4096);
    await raf.setPosition(2048);
    await raf.readInto(first);
    final last = Uint8List(2048);
    await raf.setPosition(size >= 2048 ? size - 2048 : 0);
    await raf.readInto(last);
    return '$size:${XxHash32.hash(first)}:${XxHash32.hash(last)}';
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
