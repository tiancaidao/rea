import 'dart:io';
import 'dart:typed_data';

/// A short recording from the night (snoring, talking, other sounds), kept on
/// the phone for as long as Profile › More › Sound detection says and played
/// back from the Journal's Sounds card.
class SoundClip {
  final int offsetSec; // seconds after the night started
  final String path;
  final String kind; // 'snore' | 'sound'
  final double peakDb; // loudness above the room's noise floor
  final int durationMs;
  const SoundClip(
      {required this.offsetSec,
      required this.path,
      required this.kind,
      required this.peakDb,
      required this.durationMs});

  Map<String, dynamic> toJson() => {'t': offsetSec, 'path': path, 'kind': kind, 'db': peakDb, 'ms': durationMs};
  factory SoundClip.fromJson(Map<String, dynamic> j) => SoundClip(
      offsetSec: j['t'] as int,
      path: j['path'] as String,
      kind: j['kind'] as String,
      peakDb: (j['db'] as num).toDouble(),
      durationMs: j['ms'] as int);

  bool get exists => File(path).existsSync();
}

/// How many nights of clips to keep for a Sound detection option; null keeps
/// them forever, 0 records none.
int? keepNightsFor(String option) {
  if (option.startsWith('Forever')) return null;
  return int.tryParse(option.split(' ').first) ?? 20;
}

/// 16-bit mono PCM → a playable WAV file.
Future<void> writeWav(String path, Int16List pcm, int sampleRate) async {
  final data = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  final h = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  h.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  h.setUint32(40, data.length, Endian.little);
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsBytes([...h.buffer.asUint8List(), ...data], flush: true);
}

/// Delete clip files of every night but the newest [keep] (null: keep all).
Future<void> pruneClipFiles(List<List<SoundClip>> nightsOldestFirst, int? keep) async {
  if (keep == null) return;
  final drop = nightsOldestFirst.length - keep;
  for (var i = 0; i < drop; i++) {
    for (final c in nightsOldestFirst[i]) {
      try {
        await File(c.path).delete();
      } catch (_) {}
    }
    nightsOldestFirst[i].clear();
  }
}
