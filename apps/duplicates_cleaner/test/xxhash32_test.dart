import 'dart:convert';
import 'dart:typed_data';

import 'package:duplicates_cleaner/core/xxhash32.dart';
import 'package:flutter_test/flutter_test.dart';

int h(String s) => XxHash32.hash(Uint8List.fromList(utf8.encode(s)));

void main() {
  test('matches reference XXH32 vectors', () {
    expect(h(''), 0x02CC5D05);
    expect(h('a'), 0x550D7456);
    expect(h('abc'), 0x32D153FF);
    expect(h('Nobody inspects the spammish repetition'), 0xE2293B2F);
  });
}
