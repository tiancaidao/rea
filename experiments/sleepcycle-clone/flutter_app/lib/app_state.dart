import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend/backend.dart';
import 'data/night.dart';
import 'data/recorded_night.dart';
import 'data/sleep_aid_catalog.dart';
import 'data/sound_clips.dart';
import 'device/health_connect.dart';
import 'device/notifications.dart';
import 'device/wear.dart';

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
    Notifications.I.onAction = _onNotificationAction;
    Wear.I.init();
    Wear.I.requests.listen(_onWatch);
    await RecordedNight.load();
    await _loadAudioPool();
    unawaited(loadAndPruneDownloads());
    try {
      _clipsRoot = '${(await getApplicationSupportDirectory()).path}/clips';
    } catch (_) {
      _clipsRoot = null; // tests / no file system: no clips
    }
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

  // ── night sounds ──────────────────────────────────────────────────────────
  String? _clipsRoot;

  /// Where tonight's clips go, or null when Sound detection keeps none.
  String? clipDirForTonight() {
    if (_clipsRoot == null || keepNightsFor(pref('sound_detection')) == 0) return null;
    return '$_clipsRoot/${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Drop clips older than the Sound detection setting allows.
  Future<void> pruneClips() async {
    await pruneClipFiles([for (final n in nights) n.clips], keepNightsFor(pref('sound_detection')));
    notifyListeners();
  }

  // ── morning ───────────────────────────────────────────────────────────────
  /// Set when the alarm is stopped: the tabs then run the morning flow (wake-up
  /// mood prompt, alertness test offer) for this night, and clear it.
  final ValueNotifier<Night?> morning = ValueNotifier(null);

  /// The alertness test can be taken this long after waking up.
  static const alertnessWindow = Duration(hours: 3);

  void saveAlertness(Night n, AlertnessResult r) {
    n.alertness = r;
    nightChanged(n);
  }

  /// Profile › More › Database › "Test alarm": the next tracking session rings
  /// a regular alarm 10 seconds after it starts.
  bool testAlarmArmed = false;
  DateTime? takeTestAlarm() {
    if (!testAlarmArmed) return null;
    testAlarmArmed = false;
    return DateTime.now().add(const Duration(seconds: 10));
  }

  // ── reminders ─────────────────────────────────────────────────────────────
  /// Bedtime: the alarm time minus the sleep goal (8 h when none is set).
  DateTime get bedtime {
    final goal = pref('sleep_goal');
    var minutes = 8 * 60;
    final m = RegExp(r'(\d+)h(?: (\d+)m)?').firstMatch(goal);
    if (m != null) minutes = int.parse(m.group(1)!) * 60 + int.parse(m.group(2) ?? '0');
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, alarmHour, alarmMinute).subtract(Duration(minutes: minutes));
  }

  /// Re-schedule the local reminders from the current settings.
  Future<void> rescheduleReminders() async {
    final r = pref('bedtime_reminder');
    final before = r == 'At bedtime' ? 0 : int.tryParse(r.split(' ').first);
    await Notifications.I.scheduleBedtimeReminder(before == null ? null : bedtime.subtract(Duration(minutes: before)));
    await Notifications.I.scheduleWeeklyReport(pref('weekly_report') == 'On' && pref('weekly_report_notify') == 'On');
  }

  void finishOnboarding() {
    onboarded = true;
    notifyListeners();
  }

  void logOut() {
    onboarded = false;
    tab = 0;
    if (Backend.I.user != null) {
      // signed-in data lives in the cloud; clear this device's copy
      nights.clear();
      selectedNight = null;
    }
    notifyListeners();
    unawaited(Backend.I.signOut());
  }

  /// The synced part of the state (everything but nights, which are stored
  /// one document each).
  Map<String, dynamic> get _profile => {
        'alarmHour': alarmHour,
        'alarmMinute': alarmMinute,
        'alarmMode': alarmMode,
        'prefs': _prefs,
        'sleepNotes': sleepNotes,
        'completedLessons': completedLessons.toList(),
      };

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _storeKey,
          json.encode({
            ..._profile,
            'onboarded': onboarded,
            'email': email,
            'premium': premium,
            'nights': [for (final n in nights) n.toJson()],
          }));
    } catch (_) {}
    if (Backend.I.user != null) {
      unawaited(Backend.I.saveProfile(_profile).catchError((_) {}));
    }
  }

  /// After sign-in: pull the account's profile and nights from Firestore and
  /// upload any nights tracked on this device before signing in.
  Future<void> syncFromCloud() async {
    final b = Backend.I;
    if (b.user == null) return;
    email = b.user!.email ?? email;
    try {
      final profile = await b.loadProfile();
      if (profile != null) {
        _restore({...profile, 'nights': const []});
        premium = (profile['premium'] as Map?)?['active'] == true;
      }
      final cloud = await b.loadNights();
      final cloudIds = {for (final n in cloud) b.nightId(n)};
      for (final n in nights.where((n) => !cloudIds.contains(b.nightId(n)))) {
        await b.saveNight(n);
      }
      final localIds = {for (final n in nights) b.nightId(n)};
      nights.addAll(cloud.where((n) => !localIds.contains(b.nightId(n))));
      nights.sort((a, c) => a.wokeUp.compareTo(c.wokeUp));
      selectedNight = null;
    } catch (e) {
      b.lastError = 'Sync failed: $e';
    }
    notifyListeners();
  }

  /// Persist edits to one night (mood, sleep notes).
  void nightChanged(Night n) {
    notifyListeners();
    unawaited(Backend.I.saveNight(n).catchError((_) {}));
  }

  void _restore(Map<String, dynamic> j) {
    onboarded = j['onboarded'] as bool? ?? false;
    email = j['email'] as String? ?? email;
    premium = j['premium'] as bool? ?? false;
    alarmHour = j['alarmHour'] as int? ?? alarmHour;
    alarmMinute = j['alarmMinute'] as int? ?? alarmMinute;
    alarmMode = j['alarmMode'] as int? ?? alarmMode;
    (j['prefs'] as Map?)?.forEach((k, v) => _prefs[k as String] = v as String);
    themeName.value = pref('theme');
    final notes = (j['sleepNotes'] as List?)?.cast<String>();
    if (notes != null)
      sleepNotes
        ..clear()
        ..addAll(notes);
    completedLessons.addAll((j['completedLessons'] as List? ?? const []).cast<String>());
    nights
        .addAll([for (final n in j['nights'] as List? ?? const []) Night.fromJson((n as Map).cast<String, dynamic>())]);
  }

  // ── local audio ───────────────────────────────────────────────────────────
  /// Audio files present in assets/audio/ (the extracted comparison
  /// placeholders). Empty in a clean checkout, where the real recordings in
  /// assets/free/audio/ (tools/fetch_free_media.py) play instead, and our
  /// own synthesised clips in assets/audio/own/ fill any gap.
  List<String> ambienceAudio = [];
  List<String> alarmAudio = [];

  static const ownDir = 'assets/audio/own/';
  static const freeDir = 'assets/free/audio/';

  /// The recordings bundled under [freeDir] (public domain / Creative
  /// Commons, see assets/free/CREDITS-audio.md).
  static Set<String> freeAudio = {};

  /// Free music for sleep-aid music, stories and guides without audio of
  /// their own.
  static const freeMusic = [
    'soft_breeze',
    'far_memories',
    'stillness',
    'dewdrops',
    'riddle',
    'morning_haze',
    'winter_moon',
    'slow_waltz',
    'classical_morning',
  ];
  static const ownAlarms = [
    'soft_breeze',
    'forest_clearing',
    'morning_haze',
    'first_light',
    'dewdrops',
    'classical_morning',
    'rain_and_wind',
    'far_memories',
  ];
  static const ownAmbiences = [
    'rain',
    'wind',
    'ocean',
    'fire',
    'night_forest',
    'stream',
    'brown_noise',
    'pink_noise',
    'white_noise',
    'droplets',
  ];

  Future<void> _loadAudioPool() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final audio = manifest
          .listAssets()
          .where((a) =>
              a.startsWith('assets/audio/') &&
              !a.startsWith(ownDir) &&
              (a.endsWith('.mp3') || a.endsWith('.ogg') || a.endsWith('.m4a')) &&
              !a.contains('silence'))
          .toList()
        ..sort();
      freeAudio = manifest.listAssets().where((a) => a.startsWith(freeDir)).toSet();
      alarmAudio = audio.where((a) => a.contains('alarm_sound')).toList();
      ambienceAudio = audio.where((a) => !a.contains('alarm_sound')).toList();
    } catch (_) {}
  }

  /// Our own ambience for a catalog item: matched on its title, else a stable
  /// pick, so every soundscape has a sound of its own.
  static String ownAmbienceFor(SleepAidItem item) {
    final t = '${item.id} ${item.title}'.toLowerCase();
    const keys = {
      'rain': 'rain',
      'glass': 'rain',
      'wind': 'wind',
      'ocean': 'ocean',
      'sea': 'ocean',
      'swell': 'ocean',
      'wave': 'ocean',
      'tide': 'ocean',
      'fire': 'fire',
      'ember': 'fire',
      'forest': 'night_forest',
      'cricket': 'night_forest',
      'stream': 'stream',
      'river': 'stream',
      'brown': 'brown_noise',
      'pink': 'pink_noise',
      'white': 'white_noise',
      'drop': 'droplets',
    };
    final i = item.id.codeUnits.fold(0, (a, b) => a + b);
    // birdsong for dawn, real music for anything with a duration
    if (t.contains('dawn') && freeAudio.contains('${freeDir}alarm_forest_clearing.mp3')) {
      return '${freeDir}alarm_forest_clearing.mp3';
    }
    if (item.minutes > 0) {
      final m = '${freeDir}alarm_${freeMusic[i % freeMusic.length]}.mp3';
      if (freeAudio.contains(m)) return m;
    }
    for (final e in keys.entries) {
      if (t.contains(e.key)) return _ambience(e.value);
    }
    return _ambience(ownAmbiences[i % ownAmbiences.length]);
  }

  /// A recorded ambience when we have one, else our synthesised loop.
  static String _ambience(String key) {
    final free = '${freeDir}amb_$key.mp3';
    return freeAudio.contains(free) ? free : '${ownDir}amb_$key.mp3';
  }

  /// The recording for an alarm-sound name, else our own synthesised melody
  /// (premium names reuse the free melodies in turn).
  static String ownAlarmFor(String name, List<String> allNames) {
    final free = '${freeDir}alarm_${name.toLowerCase().replaceAll(' ', '_')}.mp3';
    if (freeAudio.contains(free)) return free;
    final i = math.max(0, allNames.indexOf(name));
    return '${ownDir}alarm_${ownAlarms[i % ownAlarms.length]}.mp3';
  }

  /// Local file to play for a catalog item: its own asset if it has one,
  /// otherwise a stable pick from the local pool (ambience first for
  /// soundscapes, the melodic alarm tracks for music/stories/guides), and
  /// with no placeholders at all, our own ambience.
  String? audioFor(SleepAidItem item) {
    if (item.asset != null &&
        (freeAudio.contains(item.asset) || ambienceAudio.contains(item.asset) || alarmAudio.contains(item.asset))) {
      return item.asset;
    }
    final pool = item.minutes == 0
        ? (ambienceAudio.isNotEmpty ? ambienceAudio : alarmAudio)
        : (alarmAudio.isNotEmpty ? alarmAudio : ambienceAudio);
    if (pool.isEmpty) return ownAmbienceFor(item);
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
    if (pref('bedtime_reminder') != 'No reminder') unawaited(rescheduleReminders());
    if (!tracking) unawaited(publishToWatch());
  }

  void setAlarmMode(int m) {
    alarmMode = m;
    notifyListeners();
    if (!tracking) unawaited(publishToWatch());
  }

  int get windowMinutes => int.tryParse(pref('wake_phase')) ?? 30;

  // ── settings (key → current option label) ─────────────────────────────────
  final Map<String, String> _prefs = {
    'theme': 'Midnight',
    'sleep_goal': 'Not set',
    'alarm_sound': 'Soft breeze',
    'wake_phase': '30',
    'weekly_report': 'On',
    'weekly_report_notify': 'On',
    'bedtime_reminder': 'No reminder',
    'whats_new_seen': '',
    'home_location': '',
    'online_backup': 'On',
    'sleep_aid_download': 'Wi-Fi only',
    'sleep_aid_keep': '20 nights (recommended)',
    'wear_alarm_type': 'Automatic',
    'snore_alert': 'Off',
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

  /// Active theme label (see `AppThemeId`), mirrored out of the prefs so the
  /// app root can listen to it alone.
  final ValueNotifier<String> themeName = ValueNotifier('Midnight');

  void setPref(String key, String value) {
    _prefs[key] = value;
    if (key == 'theme') themeName.value = value;
    if (const {'bedtime_reminder', 'weekly_report', 'weekly_report_notify', 'sleep_goal'}.contains(key)) {
      unawaited(rescheduleReminders());
    }
    if (key == 'sound_detection') unawaited(pruneClips());
    if (key == 'sleep_aid_keep') unawaited(loadAndPruneDownloads());
    if (key == 'wear_alarm_type') unawaited(publishToWatch());
    if (Backend.I.user != null) unawaited(_syncPref(key).catchError((_) {}));
    notifyListeners();
  }

  /// Consent choices and "About you" also go to the API (a GDPR record and
  /// the profile used for insights).
  Future<void> _syncPref(String key) async {
    if (key.startsWith('consent_')) {
      await Backend.I.saveConsent(
          storage: pref('consent_storage') == 'true',
          sounds: pref('consent_sounds') == 'true',
          product: pref('consent_product') == 'true');
    } else if (const {'units', 'weight', 'height', 'gender', 'birth', 'survey'}.contains(key)) {
      await Backend.I.saveProperties({key: pref(key)});
    }
  }

  // ── sleep notes ───────────────────────────────────────────────────────────
  final List<String> sleepNotes = [
    'Caffeine late',
    'Big dinner',
    'Warm shower',
    'Read a book',
    'Exercise',
    'Alcohol',
    'Stress',
    'Nap',
    'Screen time',
    'Meditated',
    'Feeling sick',
    'Medication',
    'Travel',
    'Tea',
    'Outdoors',
  ];
  void notesChanged() => notifyListeners();

  // ── watch ─────────────────────────────────────────────────────────────────
  /// Whether the tracking screen is open (a night is being recorded).
  bool tracking = false;

  /// The current night was started from the watch (Alarm type › Automatic).
  bool startedFromWatch = false;

  /// Requests from the watch for the open tracking or alarm screen
  /// (stop · snooze · stop_alarm); the screen clears it after acting.
  final ValueNotifier<String?> remote = ValueNotifier(null);

  void _onWatch(String r) {
    switch (r) {
      case 'start':
        if (tracking) return;
        startedFromWatch = true;
        Notifications.I.tapped.value = 'start_watch';
      case 'stop' || 'snooze' || 'stop_alarm':
        remote.value = r;
      case 'sync':
        unawaited(publishToWatch());
      default:
        if (r.startsWith('alarm_type:')) setPref('wear_alarm_type', r.substring('alarm_type:'.length));
    }
  }

  /// Send the phone's state (tracking, alarm window, alarm type) to the watch.
  Future<void> publishToWatch({DateTime? since, DateTime? alarmStart, DateTime? alarmEnd}) => Wear.I.publish(
        tracking: tracking,
        since: since,
        alarmStart: alarmStart ??
            (alarmMode == 2 ? null : bedtimeAlarm().subtract(Duration(minutes: alarmMode == 0 ? windowMinutes : 0))),
        alarmEnd: alarmEnd ?? (alarmMode == 2 ? null : bedtimeAlarm()),
        alarmType: pref('wear_alarm_type'),
      );

  /// The next alarm time from the alarm settings.
  DateTime bedtimeAlarm() {
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day, alarmHour, alarmMinute);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  // ── nights ────────────────────────────────────────────────────────────────
  final List<Night> nights = []; // oldest first
  int? selectedNight; // index into nights; null = latest

  Night? get currentNight => nights.isEmpty ? null : nights[selectedNight ?? nights.length - 1];

  void addNight(Night n) {
    nights.add(n);
    nights.sort((a, b) => a.wokeUp.compareTo(b.wokeUp));
    selectedNight = nights.indexOf(n);
    notifyListeners();
    unawaited(Backend.I.saveNight(n).catchError((_) {}));
    // ask for a store rating after a few good nights, as the original does
    if ((nights.length == 3 || nights.length == 10) && n.quality >= 70) unawaited(_askForReview());
  }

  /// Add the nights other apps wrote to Health Connect, skipping any that
  /// overlap a night already here. Returns how many were added.
  Future<int> importHealthNights() async {
    final added = <Night>[];
    for (final s in await HealthConnect.I.importSleep()) {
      final overlaps = nights.any((n) => n.wentToBed.isBefore(s.endedAt) && n.wokeUp.isAfter(s.startedAt));
      if (overlaps) continue;
      final n = Night(
          session: s,
          weatherF: null,
          snoreMinutes: 0,
          coughs: 0,
          breathingPerHour: 0,
          regularity: 0,
          notes: {'Imported'});
      nights.add(n);
      added.add(n);
    }
    if (added.isEmpty) return 0;
    nights.sort((a, b) => a.wokeUp.compareTo(b.wokeUp));
    selectedNight = null;
    notifyListeners();
    for (final n in added) {
      unawaited(Backend.I.saveNight(n).catchError((_) {}));
    }
    return added.length;
  }

  Future<void> _askForReview() async {
    try {
      final r = InAppReview.instance;
      if (await r.isAvailable()) await r.requestReview();
    } catch (_) {}
  }

  void selectNight(int i) {
    selectedNight = i;
    notifyListeners();
  }

  void deleteNight(Night n) {
    nights.remove(n);
    selectedNight = null;
    notifyListeners();
    unawaited(Backend.I.deleteNight(n).catchError((_) {}));
  }

  void eraseAll() {
    nights.clear();
    selectedNight = null;
    notifyListeners();
    unawaited(Backend.I.eraseData().catchError((_) {}));
  }

  /// Seed a week of synthetic nights so every screen can be exercised
  /// without tracking for real (Profile › More › Database).
  void loadSampleNights([int count = 7]) {
    final today = DateTime.now();
    final rng = math.Random();
    for (var d = count; d >= 1; d--) {
      final morning = DateTime(today.year, today.month, today.day - d + 1, 6 + rng.nextInt(2), rng.nextInt(60));
      nights.add(sampleNight(morning, 1 + rng.nextInt(1 << 30)));
    }
    nights.sort((a, b) => a.wokeUp.compareTo(b.wokeUp));
    selectedNight = null;
    notifyListeners();
    for (final n in nights) {
      unawaited(Backend.I.saveNight(n).catchError((_) {}));
    }
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
    _armFade();
    final file = item.url == null ? audioFor(item) : null;
    if (item.url == null && file == null) return; // nothing to play: mock playback
    try {
      await player.setVolume(1);
      if (item.url != null) {
        final cached = sleepAidCache[item.id];
        if (cached != null) {
          await player.setFilePath(cached); // downloaded on the track sheet
        } else {
          await player.setUrl(item.url!); // streamed from Cloud Storage
        }
      } else {
        await player.setAsset(file!);
      }
      await player.play();
    } catch (_) {
      // file missing: keep the mock "playing" state
    }
    unawaited(Notifications.I.showNowPlaying(item.title, playing: true));
  }

  /// Stop the sleep aid and clear its player notification.
  Future<void> stopSleepAid() async {
    await pauseSleepAid();
    await Notifications.I.cancel(Notifications.playerId);
  }

  /// Pause/Play/Stop from the player notification.
  void _onNotificationAction(String id) {
    if (id == 'aid_toggle') toggleSleepAid();
    if (id == 'aid_stop') stopSleepAid();
  }

  Future<void> pauseSleepAid() async {
    _fadeTimer?.cancel();
    sleepAidPlaying = false;
    notifyListeners();
    try {
      await player.pause();
    } catch (_) {}
    final item = sleepAid;
    if (item != null) unawaited(Notifications.I.showNowPlaying(item.title, playing: false));
  }

  Future<void> toggleSleepAid() => sleepAidPlaying ? pauseSleepAid() : playSleepAid();

  /// Downloaded streamed tracks (item id → local file), from the track sheet.
  final Map<String, String> sleepAidCache = {};

  /// Whether the Download files setting allows downloading on the current
  /// connection ("Wi-Fi only" refuses mobile data).
  Future<bool> downloadsAllowedNow() async {
    if (pref('sleep_aid_download') != 'Wi-Fi only') return true;
    try {
      final c = await Connectivity().checkConnectivity();
      return c.contains(ConnectivityResult.wifi) || c.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  /// Find downloads from earlier runs and delete those older than Keep
  /// downloaded files for allows.
  Future<void> loadAndPruneDownloads() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final keep = pref('sleep_aid_keep');
      final days = keep.startsWith('Forever') ? null : int.tryParse(keep.split(' ').first);
      for (final e in dir.listSync().whereType<File>()) {
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('sleepaid_')) continue;
        final age = DateTime.now().difference(e.statSync().modified);
        if (days != null && age > Duration(days: days)) {
          e.deleteSync();
        } else {
          sleepAidCache[name.substring('sleepaid_'.length)] = e.path;
        }
      }
    } catch (_) {}
  }

  // ── sleep-aid fade-out ────────────────────────────────────────────────────
  Timer? _fadeTimer;

  /// Minutes until the sleep aid fades out, from Profile › Sleep aid. "Smart"
  /// fades once tracking sees you fall asleep ([sleepOnsetDetected]), with 45
  /// minutes as the cap; "All night" never fades.
  int? get fadeMinutes {
    final v = pref('sleep_aid_fade');
    if (v.startsWith('All')) return null;
    if (v.startsWith('Smart')) return 45;
    return int.tryParse(v.split(' ').first);
  }

  void _armFade() {
    _fadeTimer?.cancel();
    final m = fadeMinutes;
    if (m == null) return;
    _fadeTimer = Timer(Duration(minutes: m), fadeOutSleepAid);
  }

  /// Called by the tracking screen when the night's first sleep epoch shows up.
  void sleepOnsetDetected() {
    if (sleepAidPlaying && pref('sleep_aid_fade').startsWith('Smart')) {
      _fadeTimer?.cancel();
      _fadeTimer = Timer(const Duration(minutes: 5), fadeOutSleepAid);
    }
  }

  /// Ramp the volume down over a minute, then pause.
  Future<void> fadeOutSleepAid({Duration over = const Duration(seconds: 60)}) async {
    if (!sleepAidPlaying) return;
    const steps = 30;
    for (var i = steps; i >= 0; i--) {
      if (!sleepAidPlaying) return;
      try {
        await player.setVolume(i / steps);
      } catch (_) {}
      await Future.delayed(over ~/ steps);
    }
    await pauseSleepAid();
    try {
      await player.setVolume(1);
    } catch (_) {}
  }
}
