import 'package:flutter/painting.dart';

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
  const SleepAidItem({
    required this.id,
    required this.title,
    this.description = '',
    this.minutes = 0,
    this.author = 'Sleep Tracker Studio',
    this.narrator = '',
    required this.art,
    this.asset,
  });
}

enum SectionLayout { hero, grid }

class SleepAidSection {
  final String title;
  final SectionLayout layout;
  final List<SleepAidItem> items;
  const SleepAidSection(this.title, this.layout, this.items);
}

class SleepAidCatalog {
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
