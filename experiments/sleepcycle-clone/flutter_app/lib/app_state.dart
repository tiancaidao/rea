import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/night.dart';
import 'data/recorded_night.dart';
import 'data/sleep_aid_catalog.dart';

/// App-wide state for the prototype: alarm, settings, recorded nights and the
/// chosen sleep-aid track. Persisted locally with shared_preferences (a real
/// build would use a local DB and sync via the backend).
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  // ── persistence ───────────────────────────────────────────────────────────
  static const _storeKey = 'app_state_v1';
  bool onboarded = false; // finished onboarding + account + trial screens
  Timer? _saveTimer;
  bool _loaded = false;

  /// Restore saved state and warm up local assets. Call once before runApp.
  Future<void> load() async {
    await RecordedNight.load();
    await _loadAudioPool();
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storeKey);
      if (raw != null) _restore(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      // corrupt or unavailable storage: start fresh
    }
    _loaded = true;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_loaded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  void finishOnboarding() {
    onboarded = true;
    notifyListeners();
  }

  void logOut() {
    onboarded = false;
    tab = 0;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _storeKey,
          json.encode({
            'onboarded': onboarded,
            'email': email,
            'premium': premium,
            'alarmHour': alarmHour,
            'alarmMinute': alarmMinute,
            'alarmMode': alarmMode,
            'prefs': _prefs,
            'sleepNotes': sleepNotes,
            'completedLessons': completedLessons.toList(),
            'nights': [for (final n in nights) n.toJson()],
          }));
    } catch (_) {}
  }

  void _restore(Map<String, dynamic> j) {
    onboarded = j['onboarded'] as bool? ?? false;
    email = j['email'] as String? ?? email;
    premium = j['premium'] as bool? ?? false;
    alarmHour = j['alarmHour'] as int? ?? alarmHour;
    alarmMinute = j['alarmMinute'] as int? ?? alarmMinute;
    alarmMode = j['alarmMode'] as int? ?? alarmMode;
    (j['prefs'] as Map?)?.forEach((k, v) => _prefs[k as String] = v as String);
    final notes = (j['sleepNotes'] as List?)?.cast<String>();
    if (notes != null) sleepNotes
      ..clear()
      ..addAll(notes);
    completedLessons.addAll((j['completedLessons'] as List? ?? const []).cast<String>());
    nights.addAll([
      for (final n in j['nights'] as List? ?? const []) Night.fromJson((n as Map).cast<String, dynamic>())
    ]);
  }

  // ── local audio ───────────────────────────────────────────────────────────
  /// Audio files present in assets/audio/ (the extracted comparison
  /// placeholders). Empty in a clean checkout, where playback is mocked.
  List<String> ambienceAudio = [];
  List<String> alarmAudio = [];

  Future<void> _loadAudioPool() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final audio = manifest.listAssets().where((a) => a.startsWith('assets/audio/') &&
          (a.endsWith('.mp3') || a.endsWith('.ogg') || a.endsWith('.m4a')) &&
          !a.contains('silence')).toList()
        ..sort();
      alarmAudio = audio.where((a) => a.contains('alarm_sound')).toList();
      ambienceAudio = audio.where((a) => !a.contains('alarm_sound')).toList();
    } catch (_) {}
  }

  /// Local file to play for a catalog item: its own asset if it has one,
  /// otherwise a stable pick from the local pool (ambience first for
  /// soundscapes, the melodic alarm tracks for music/stories/guides).
  String? audioFor(SleepAidItem item) {
    if (item.asset != null && (ambienceAudio.contains(item.asset) || alarmAudio.contains(item.asset))) {
      return item.asset;
    }
    final pool = item.minutes == 0
        ? (ambienceAudio.isNotEmpty ? ambienceAudio : alarmAudio)
        : (alarmAudio.isNotEmpty ? alarmAudio : ambienceAudio);
    if (pool.isEmpty) return null;
    return pool[item.id.codeUnits.fold(0, (a, b) => a + b) % pool.length];
  }

  // ── navigation ────────────────────────────────────────────────────────────
  int tab = 0; // Sleep · Programs · Journal · Statistics · Profile
  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  // ── account ───────────────────────────────────────────────────────────────
  String email = 'demo@example.com';
  bool premium = false;

  // ── alarm ─────────────────────────────────────────────────────────────────
  int alarmHour = 7;
  int alarmMinute = 30;
  int alarmMode = 0; // 0 smart window · 1 regular alarm · 2 no alarm

  void setAlarm(int h, int m) {
    alarmHour = h;
    alarmMinute = m;
    notifyListeners();
  }

  void setAlarmMode(int m) {
    alarmMode = m;
    notifyListeners();
  }

  int get windowMinutes => int.tryParse(pref('wake_phase')) ?? 30;

  // ── settings (key → current option label) ─────────────────────────────────
  final Map<String, String> _prefs = {
    'sleep_goal': 'Not set',
    'alarm_sound': 'Soft breeze',
    'wake_phase': '30',
    'watch_alarm_type': 'Automatic',
    'watch_auto_start': 'Off',
    'weekly_report': 'On',
    'weekly_report_notify': 'On',
    'online_backup': 'On',
    'sleep_aid_download': 'Wi-Fi only',
    'sleep_aid_keep': '20 nights (recommended)',
    'sleep_aid_fade': '30 minutes',
    'sleep_notes': 'Hide',
    'wake_up_mood': 'Hide',
    'weather': 'Hide',
    'whos_snoring': 'Off',
    'motion_detection': 'Microphone (recommended)',
    'sound_detection': '20 nights (recommended)',
    'placement_reminders': 'On',
    'snooze': 'Smart (recommended)',
    'vibration': 'As backup',
    'battery_warning': 'On',
    'health_connect': 'Off',
    'units': 'Metric',
    'weight': '—',
    'height': '—',
    'gender': '—',
    'birth': '—',
    'survey': 'No',
    'consent_storage': 'true',
    'consent_sounds': 'false',
    'consent_product': 'true',
  };
  String pref(String key) => _prefs[key] ?? '';
  void setPref(String key, String value) {
    _prefs[key] = value;
    notifyListeners();
  }

  // ── sleep notes ───────────────────────────────────────────────────────────
  final List<String> sleepNotes = [
    'Caffeine late', 'Big dinner', 'Warm shower', 'Read a book', 'Exercise',
    'Alcohol', 'Stress', 'Nap', 'Screen time', 'Meditated', 'Feeling sick',
    'Medication', 'Travel', 'Tea', 'Outdoors',
  ];
  void notesChanged() => notifyListeners();

  // ── nights ────────────────────────────────────────────────────────────────
  final List<Night> nights = []; // oldest first
  int? selectedNight; // index into nights; null = latest

  Night? get currentNight =>
      nights.isEmpty ? null : nights[selectedNight ?? nights.length - 1];

  void addNight(Night n) {
    nights.add(n);
    nights.sort((a, b) => a.wokeUp.compareTo(b.wokeUp));
    selectedNight = nights.indexOf(n);
    notifyListeners();
  }

  void selectNight(int i) {
    selectedNight = i;
    notifyListeners();
  }

  void deleteNight(Night n) {
    nights.remove(n);
    selectedNight = null;
    notifyListeners();
  }

  void eraseAll() {
    nights.clear();
    selectedNight = null;
    notifyListeners();
  }

  /// Seed a week of synthetic nights so every screen can be exercised
  /// without tracking for real (Profile › More › Database).
  void loadSampleNights([int count = 7]) {
    final today = DateTime.now();
    final rng = math.Random();
    for (var d = count; d >= 1; d--) {
      final morning = DateTime(today.year, today.month, today.day - d + 1, 6 + rng.nextInt(2),
          rng.nextInt(60));
      nights.add(sampleNight(morning, 1 + rng.nextInt(1 << 30)));
    }
    nights.sort((a, b) => a.wokeUp.compareTo(b.wokeUp));
    selectedNight = null;
    notifyListeners();
  }

  // ── programs ──────────────────────────────────────────────────────────────
  final Set<String> completedLessons = {};
  void completeLesson(String id) {
    completedLessons.add(id);
    notifyListeners();
  }

  // ── sleep aid ─────────────────────────────────────────────────────────────
  final AudioPlayer player = AudioPlayer()..setLoopMode(LoopMode.one);
  SleepAidItem? sleepAid;
  bool sleepAidPlaying = false;

  Future<void> chooseSleepAid(SleepAidItem item) async {
    sleepAid = item;
    await playSleepAid();
  }

  Future<void> playSleepAid() async {
    final item = sleepAid;
    if (item == null) return;
    sleepAidPlaying = true;
    notifyListeners();
    final file = audioFor(item);
    if (file == null) return; // streamed in a real build: mock playback
    try {
      await player.setAsset(file);
      await player.play();
    } catch (_) {
      // placeholder audio not extracted locally: keep the mock "playing" state
    }
  }

  Future<void> pauseSleepAid() async {
    sleepAidPlaying = false;
    notifyListeners();
    try {
      await player.pause();
    } catch (_) {}
  }

  Future<void> toggleSleepAid() =>
      sleepAidPlaying ? pauseSleepAid() : playSleepAid();
}
