import 'dart:convert';
import 'package:flutter/services.dart';

/// Loads the sleep-aid catalog. In a comparison build this reads the real
/// `assets/data/sleep_aid_index.json` lifted from the APK (gitignored); when
/// that's absent it returns a small built-in catalog so the screen still works.
class SleepAidCatalog {
  final String categoryTitle;
  final List<SleepAidTrack> tracks;
  SleepAidCatalog(this.categoryTitle, this.tracks);

  static Future<SleepAidCatalog> load() async {
    try {
      final raw = json.decode(
          await rootBundle.loadString('assets/data/sleep_aid_index.json')) as Map<String, dynamic>;
      final cat = (raw['categories'] as List).first as Map<String, dynamic>;
      final en = (cat['languages'] as List)
          .firstWhere((l) => l['code'] == 'en') as Map<String, dynamic>;
      final pkgs = (raw['packages'] as List).cast<Map<String, dynamic>>();
      final tracks = <SleepAidTrack>[];
      for (var i = 0; i < pkgs.length; i++) {
        final p = pkgs[i];
        final title = ((p['languages'] as List)
            .firstWhere((l) => l['code'] == 'en')['title']) as String;
        tracks.add(SleepAidTrack(
          id: '${p['id']}',
          title: title,
          asset: _assetFor(title),
          premium: i >= 3, // first few free, rest premium — mirrors the original
        ));
      }
      return SleepAidCatalog(en['title'] as String, tracks);
    } catch (_) {
      return SleepAidCatalog('Ambience', const [
        SleepAidTrack(id: 'rain', title: 'Rain & wind', asset: 'assets/audio/rain_and_wind.mp3'),
        SleepAidTrack(id: 'dawn', title: 'Gentle dawn', asset: 'assets/audio/gentle_dawn.mp3'),
        SleepAidTrack(id: 'drops', title: 'Morning drops', asset: 'assets/audio/morning_drops.mp3'),
      ]);
    }
  }

  // Map a few catalog titles to the real audio we have locally; the rest are
  // "download" placeholders (no bundled file) just like the streamed originals.
  static String? _assetFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('rain') || t.contains('wind') || t.contains('brook') || t.contains('ocean')) {
      return 'assets/audio/rain_and_wind.mp3';
    }
    return null;
  }
}

class SleepAidTrack {
  final String id;
  final String title;
  final String? asset; // local file, or null = streamed/download (mock)
  final bool premium;
  const SleepAidTrack({
    required this.id,
    required this.title,
    this.asset,
    this.premium = false,
  });
}
