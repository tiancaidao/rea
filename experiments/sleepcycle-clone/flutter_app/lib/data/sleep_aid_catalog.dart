import 'package:flutter/painting.dart';
import '../backend/backend.dart';

/// Sleep-aid catalog, organised like the original: a featured item, then
/// themed sections that render as large "hero" cards or a 2-column tile grid,
/// each ending in "Show all (n)". All titles and descriptions here are our own
/// original placeholder content; in production the catalog is server-driven
/// (see ../mock-api `/v1/sleep-aid`) and audio is streamed + cached.
///
/// Items with an [SleepAidItem.asset] play a local file when the gitignored
/// comparison placeholders are present; the rest use mock playback.
class SleepAidItem {
  final String id;
  final String title;
  final String description;
  final int minutes;
  final String author;
  final String narrator;
  final List<Color> art; // gradient standing in for cover artwork
  final String? asset;
  final String? url; // streamed media (signed URL from the API)
  final bool? premiumFlag; // from the server catalog; built-in items use [SleepAidCatalog.freeIds]
  const SleepAidItem({
    required this.id,
    required this.title,
    this.description = '',
    this.minutes = 0,
    this.author = 'Sleep Tracker Studio',
    this.narrator = '',
    required this.art,
    this.asset,
    this.url,
    this.premiumFlag,
  });

  /// Premium content (a badge on the tile; free users get the paywall).
  bool get premium => premiumFlag ?? !SleepAidCatalog.freeIds.contains(id);

  factory SleepAidItem.fromJson(Map<String, dynamic> j) {
    Color hex(String s) => Color(int.parse(s.replaceFirst('#', 'FF'), radix: 16));
    final art = (j['art'] as List?)?.cast<String>() ?? const ['#2E7D9A', '#0D2236'];
    return SleepAidItem(
      id: j['id'] as String,
      title: j['title'] as String,
      description: (j['description'] as String?) ?? '',
      minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      author: (j['author'] as String?) ?? 'Sleep Tracker Studio',
      narrator: (j['narrator'] as String?) ?? '',
      art: [hex(art[0]), hex(art[1])],
      url: j['url'] as String?,
      premiumFlag: j['premium'] as bool?,
    );
  }
}

enum SectionLayout { hero, grid }

class SleepAidSection {
  final String title;
  final SectionLayout layout;
  final List<SleepAidItem> items;
  const SleepAidSection(this.title, this.layout, this.items);
}

class SleepAidCatalog {
  /// What the UI shows: the server catalog once fetched, else the built-in one.
  static List<SleepAidSection> current = sections;
  static SleepAidItem currentFeatured = featured;

  static Future<bool> refresh() async {
    final r = await fetchRemote();
    if (r == null) return false;
    currentFeatured = r.$1;
    current = r.$2;
    return true;
  }

  /// Catalog from the API (server-driven, streamed media), or null when the
  /// backend is off/unreachable — callers then use the built-in [sections].
  static Future<(SleepAidItem, List<SleepAidSection>)?> fetchRemote() async {
    try {
      final j = await Backend.I.sleepAidCatalog();
      final raw = (j?['sections'] as List?) ?? const [];
      if (raw.isEmpty) return null;
      final sections = [
        for (final s in raw.cast<Map<String, dynamic>>())
          SleepAidSection(
            s['title'] as String,
            s['layout'] == 'grid' ? SectionLayout.grid : SectionLayout.hero,
            [for (final it in (s['items'] as List).cast<Map<String, dynamic>>()) SleepAidItem.fromJson(it)],
          ),
      ];
      final all = sections.expand((s) => s.items);
      final feat = all.firstWhere((i) => i.id == j!['featuredId'], orElse: () => all.first);
      return (feat, sections);
    } catch (_) {
      return null;
    }
  }

  /// Built-in items anyone can play; the rest are Premium.
  static const freeIds = {
    'slow-exhale',
    'box-breath',
    'rain-wind',
    'dawn',
    'drops',
    'brown',
    'pink',
    'lighthouse',
    'low-tide',
    'first-snow',
    'twinkle',
  };

  static const _dusk = [Color(0xFFF0A36B), Color(0xFF3B2F5C)];
  static const _sea = [Color(0xFF2E7D9A), Color(0xFF0D2236)];
  static const _rain = [Color(0xFF3C5A78), Color(0xFF101828)];
  static const _ember = [Color(0xFFE2683C), Color(0xFF2A1420)];
  static const _forest = [Color(0xFF3F7A57), Color(0xFF0F2219)];
  static const _violet = [Color(0xFF7C5CFF), Color(0xFF15122E)];
  static const _city = [Color(0xFFB65A3A), Color(0xFF1B1A2E)];

  static const featured = SleepAidItem(
    id: 'slow-exhale',
    title: 'Slow Exhale',
    description: 'A short guided breath that lengthens each exhale to settle a busy mind.',
    minutes: 11,
    narrator: 'Maya Lind',
    art: _dusk,
  );

  static const sections = <SleepAidSection>[
    SleepAidSection('Breathing', SectionLayout.hero, [
      featured,
      SleepAidItem(
          id: 'box-breath',
          title: 'Box Breathing for Bed',
          description: 'Four even counts in, hold, out, hold — a steady rhythm to slow down.',
          minutes: 8,
          narrator: 'Maya Lind',
          art: _sea),
      SleepAidItem(
          id: 'body-soften',
          title: 'Soften the Body',
          description: 'Breathe into each muscle group and let it go heavy.',
          minutes: 14,
          narrator: 'Maya Lind',
          art: _forest),
    ]),
    SleepAidSection('Ambience', SectionLayout.grid, [
      SleepAidItem(id: 'rain-wind', title: 'Rain & wind', art: _rain, asset: 'assets/audio/rain_and_wind.mp3'),
      SleepAidItem(id: 'dawn', title: 'Early dawn', art: _dusk, asset: 'assets/audio/gentle_dawn.mp3'),
      SleepAidItem(id: 'drops', title: 'Droplets', art: _sea, asset: 'assets/audio/morning_drops.mp3'),
      SleepAidItem(id: 'fire', title: 'Fireplace', art: _ember),
      SleepAidItem(id: 'forest', title: 'Night forest', art: _forest),
      SleepAidItem(id: 'brown', title: 'Brown noise', art: _city),
      SleepAidItem(id: 'pink', title: 'Pink noise', art: _violet),
      SleepAidItem(id: 'swell', title: 'Ocean swell', art: _sea),
    ]),
    SleepAidSection('Stories', SectionLayout.hero, [
      SleepAidItem(
          id: 'lighthouse',
          title: 'The Lighthouse Keeper',
          description: 'A slow tale of a quiet island, told to drift off to.',
          minutes: 26,
          author: 'Ida Moberg',
          narrator: 'Tom Ashby',
          art: _city),
      SleepAidItem(
          id: 'night-train',
          title: 'Night Train North',
          description: 'Rails humming through snowy forests until morning.',
          minutes: 31,
          author: 'Ida Moberg',
          narrator: 'Tom Ashby',
          art: _rain),
    ]),
    SleepAidSection('Music', SectionLayout.hero, [
      SleepAidItem(
          id: 'low-tide',
          title: 'Low Tide Piano',
          description: 'Sparse piano phrases over soft tape hiss.',
          minutes: 24,
          author: 'Northlight Ensemble',
          art: _sea,
          asset: 'assets/audio/mozarts_morning.mp3'),
      SleepAidItem(
          id: 'drift',
          title: 'Drift',
          description: 'Warm synth pads that slowly fall away.',
          minutes: 40,
          author: 'Northlight Ensemble',
          art: _violet),
    ]),
    SleepAidSection('ASMR', SectionLayout.grid, [
      SleepAidItem(id: 'pages', title: 'Turning pages', art: _dusk),
      SleepAidItem(id: 'brush', title: 'Soft brush', art: _violet),
      SleepAidItem(id: 'tapping', title: 'Tapping', art: _ember),
      SleepAidItem(id: 'window', title: 'Rain on glass', art: _rain),
    ]),
    SleepAidSection('Winter evenings', SectionLayout.hero, [
      SleepAidItem(
          id: 'first-snow',
          title: 'First Snow',
          description: 'Muffled footsteps and a crackling stove in a cabin far from town.',
          minutes: 18,
          narrator: 'Ida Moberg',
          art: _rain),
      SleepAidItem(
          id: 'long-night',
          title: 'The Long Night',
          description: 'A drowsy walk through a village as the lights go out one by one.',
          minutes: 22,
          narrator: 'Tom Ashby',
          art: _violet),
    ]),
    SleepAidSection('Spatial audio', SectionLayout.grid, [
      SleepAidItem(id: 'sp-rain', title: 'Rain all around', art: _rain),
      SleepAidItem(id: 'sp-shore', title: 'On the shore', art: _sea),
      SleepAidItem(id: 'sp-forest', title: 'Forest at night', art: _forest),
      SleepAidItem(id: 'sp-fire', title: 'By the fire', art: _ember),
    ]),
    SleepAidSection('Classical', SectionLayout.hero, [
      SleepAidItem(
          id: 'nocturne',
          title: 'Quiet Nocturnes',
          description: 'Slow solo piano, recorded close and soft.',
          minutes: 35,
          author: 'Northlight Ensemble',
          art: _violet),
      SleepAidItem(
          id: 'strings',
          title: 'Strings at Dusk',
          description: 'A string quartet in its gentlest register.',
          minutes: 28,
          author: 'Northlight Ensemble',
          art: _dusk),
    ]),
    SleepAidSection('Bedtime rhymes', SectionLayout.grid, [
      SleepAidItem(id: 'twinkle', title: 'Little star', art: _violet),
      SleepAidItem(id: 'moon-boat', title: 'The moon boat', art: _sea),
      SleepAidItem(id: 'sleepy-bear', title: 'Sleepy bear', art: _forest),
      SleepAidItem(id: 'counting', title: 'Counting sheep', art: _dusk),
    ]),
    SleepAidSection('Guides', SectionLayout.hero, [
      SleepAidItem(
          id: 'body-scan',
          title: 'Body Scan',
          description: 'Move your attention slowly from your toes to your head.',
          minutes: 15,
          narrator: 'Maya Lind',
          art: _forest),
      SleepAidItem(
          id: 'let-go',
          title: 'Letting Go of the Day',
          description: 'Put today\'s thoughts down, one by one.',
          minutes: 10,
          narrator: 'Maya Lind',
          art: _city),
    ]),
    SleepAidSection('Sleep coaching', SectionLayout.hero, [
      SleepAidItem(
          id: 'why-3am',
          title: 'Why we wake at 3 a.m.',
          description: 'What night waking is, and what actually helps.',
          minutes: 9,
          narrator: 'Dr. Sam Okafor',
          art: _dusk),
      SleepAidItem(
          id: 'wind-down',
          title: 'Building a wind-down',
          description: 'A 30-minute routine you can stick to.',
          minutes: 12,
          narrator: 'Dr. Sam Okafor',
          art: _forest),
    ]),
  ];
}
