import 'dart:convert';
import 'package:flutter/services.dart';

/// Runtime string table. Loads `assets/data/strings.en.json` if present (the
/// local comparison build drops the real APK copy there — gitignored, never
/// shipped), otherwise falls back to `strings.en.sample.json`, our own original
/// copy that ships with the repo. Keeping text in data (not hard-coded in
/// widgets) is also what makes the app localizable, which the original is.
class S {
  static Map<String, dynamic> _m = const {};

  static Future<void> load() async {
    for (final path in const [
      'assets/data/strings.en.json',
      'assets/data/strings.en.sample.json',
    ]) {
      try {
        _m = json.decode(await rootBundle.loadString(path)) as Map<String, dynamic>;
        return;
      } catch (_) {
        // try next source
      }
    }
  }

  static String get(String key, [String fallback = '']) =>
      (_m[key] as String?) ?? fallback;

  static List<SleepNote> get sleepNotes {
    final raw = (_m['sleep_notes_list'] as List?) ?? const [];
    return raw
        .map((e) => SleepNote(
              e['id'] as String,
              e['title'] as String,
              (e['about'] as String?) ?? '',
            ))
        .toList();
  }
}

class SleepNote {
  final String id;
  final String title;
  final String about;
  const SleepNote(this.id, this.title, this.about);
}
