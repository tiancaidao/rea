import 'dart:typed_data';

/// XXH32, ported from the original app's `KHash` class (same primes, same
/// round structure). Used for the "same content" fingerprint.
class XxHash32 {
  static const int _p1 = 0x9E3779B1;
  static const int _p2 = 0x85EBCA77;
  static const int _p3 = 0xC2B2AE3D;
  static const int _p4 = 0x27D4EB2F;
  static const int _p5 = 0x165667B1;
  static const int _mask = 0xFFFFFFFF;

  static int _rotl(int x, int r) => ((x << r) | (x >> (32 - r))) & _mask;

  static int _mul(int a, int b) {
    // 32-bit multiply without overflowing 53-bit JS-safe ints on web.
    final aHi = (a >> 16) & 0xFFFF, aLo = a & 0xFFFF;
    return ((aLo * b) + (((aHi * b) & 0xFFFF) << 16)) & _mask;
  }

  static int _round(int acc, int input) =>
      _mul(_rotl((acc + _mul(input, _p2)) & _mask, 13), _p1);

  /// Hashes [data] in one shot.
  static int hash(Uint8List data, [int seed = 0]) {
    final bd = ByteData.sublistView(data);
    final len = data.length;
    var i = 0;
    int h;
    if (len >= 16) {
      var v1 = (seed + _p1 + _p2) & _mask;
      var v2 = (seed + _p2) & _mask;
      var v3 = seed & _mask;
      var v4 = (seed - _p1) & _mask;
      final limit = len - 16;
      do {
        v1 = _round(v1, bd.getUint32(i, Endian.little));
        v2 = _round(v2, bd.getUint32(i + 4, Endian.little));
        v3 = _round(v3, bd.getUint32(i + 8, Endian.little));
        v4 = _round(v4, bd.getUint32(i + 12, Endian.little));
        i += 16;
      } while (i <= limit);
      h = (_rotl(v1, 1) + _rotl(v2, 7) + _rotl(v3, 12) + _rotl(v4, 18)) & _mask;
    } else {
      h = (seed + _p5) & _mask;
    }
    h = (h + len) & _mask;
    while (i <= len - 4) {
      h = (h + _mul(bd.getUint32(i, Endian.little), _p3)) & _mask;
      h = _mul(_rotl(h, 17), _p4);
      i += 4;
    }
    while (i < len) {
      h = (h + _mul(data[i], _p5)) & _mask;
      h = _mul(_rotl(h, 11), _p1);
      i++;
    }
    h ^= h >> 15;
    h = _mul(h, _p2);
    h ^= h >> 13;
    h = _mul(h, _p3);
    h ^= h >> 16;
    return h & _mask;
  }
}
