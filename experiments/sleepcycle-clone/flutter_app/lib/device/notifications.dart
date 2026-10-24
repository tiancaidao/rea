import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications, with one channel per kind as in the original (alarm,
/// bedtime / "set alarm" reminder, alertness-game reminder, weekly report,
/// online backup, sleep-aid player, trial). Everything here is scheduled on
/// the device; nothing needs a push server.
///
/// The alarm itself rings in-app while the tracking screen runs (see
/// `AlarmController`); [scheduleAlarmBackup] is the safety net that still
/// rings through the OS alarm clock if the app was killed overnight.
class Notifications {
  Notifications._();
  static final Notifications I = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Payload of the notification that launched or resumed the app (e.g.
  /// 'alarm' → open the ringing screen), consumed by the app shell.
  final ValueNotifier<String?> tapped = ValueNotifier(null);

  static const alarmId = 1, bedtimeId = 2, weeklyId = 3, alertnessId = 4, trialId = 5, batteryId = 6, playerId = 7;

  /// Handles a tapped notification action button (the sleep-aid player's
  /// 'aid_toggle' / 'aid_stop'); set by the app state.
  void Function(String actionId)? onAction;

  static const _alarm = AndroidNotificationDetails('alarm', 'Alarm',
      channelDescription: 'Your wake-up alarm',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public);
  static const _bedtime = AndroidNotificationDetails('bedtime_reminder', 'Set alarm reminder',
      channelDescription: 'A reminder to start tracking at bedtime');
  static const _alertness = AndroidNotificationDetails('alertness_reminder', 'Alertness test reminder',
      channelDescription: 'A one-time reminder to take the morning alertness test');
  static const _weekly = AndroidNotificationDetails('weekly_report', 'Weekly report',
      channelDescription: 'When last week\'s summary is ready');
  static const _trial =
      AndroidNotificationDetails('trial', 'Free trial', channelDescription: 'A reminder before your free trial ends');
  static const _battery = AndroidNotificationDetails('battery', 'Battery warning',
      channelDescription: 'Low battery while tracking', importance: Importance.high, priority: Priority.high);

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // unknown zone id: schedules fall back to UTC offsets of tz.local
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.actionId != null && r.actionId!.isNotEmpty) {
            onAction?.call(r.actionId!);
          } else {
            tapped.value = r.payload;
          }
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) tapped.value = launch!.notificationResponse?.payload;
      _ready = true;
    } catch (_) {
      // tests / unsupported platforms: notifications become no-ops
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Ask for notification permission (Android 13+, iOS). Onboarding calls this
  /// from its notifications step; the alarm adds exact-alarm and full-screen.
  Future<bool> requestPermission({bool alarm = false}) async {
    if (!_ready) return false;
    try {
      final ok = await _android?.requestNotificationsPermission() ??
          await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true, badge: true) ??
          false;
      if (alarm) {
        await _android?.requestExactAlarmsPermission();
        await _android?.requestFullScreenIntentPermission();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  tz.TZDateTime _at(DateTime t) => tz.TZDateTime.from(t, tz.local);

  Future<void> _schedule(int id, DateTime at, String title, String body, AndroidNotificationDetails android,
      {String? payload,
      DateTimeComponents? repeat,
      AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle}) async {
    if (!_ready || !at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: _at(at),
        title: title,
        body: body,
        payload: payload,
        matchDateTimeComponents: repeat,
        androidScheduleMode: mode,
        notificationDetails: NotificationDetails(
            android: android, iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive)),
      );
    } catch (_) {
      // exact alarms not permitted: try inexact once more
      if (mode != AndroidScheduleMode.inexactAllowWhileIdle) {
        await _schedule(id, at, title, body, android, payload: payload, repeat: repeat);
      }
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  // ── alarm ──────────────────────────────────────────────────────────────────
  Future<void> scheduleAlarmBackup(DateTime at) =>
      _schedule(alarmId, at, 'Good morning', 'Time to wake up. Tap to stop the alarm.', _alarm.copyWithFlags(),
          payload: 'alarm', mode: AndroidScheduleMode.alarmClock);

  /// Shown while ringing so the alarm can be reached from the lock screen.
  Future<void> showAlarmNow() async {
    if (!_ready) return;
    try {
      await _plugin.show(
          id: alarmId,
          title: 'Good morning',
          body: 'Your alarm is ringing',
          payload: 'alarm',
          notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails('alarm_active', 'Alarm is active',
                  channelDescription: 'Shown while the alarm rings (silent; the app plays the sound)',
                  importance: Importance.max,
                  priority: Priority.max,
                  category: AndroidNotificationCategory.alarm,
                  fullScreenIntent: true,
                  playSound: false,
                  enableVibration: false,
                  ongoing: true,
                  autoCancel: false)));
    } catch (_) {}
  }

  // ── reminders ──────────────────────────────────────────────────────────────
  /// Daily "start tracking" reminder at [time] (null cancels it).
  Future<void> scheduleBedtimeReminder(DateTime? time) async {
    await cancel(bedtimeId);
    if (time == null) return;
    var at = time;
    while (!at.isAfter(DateTime.now())) {
      at = at.add(const Duration(days: 1));
    }
    await _schedule(
        bedtimeId, at, 'Bedtime reminder', 'Bedtime is near. Start tracking and put your phone by your bed.', _bedtime,
        payload: 'sleep', repeat: DateTimeComponents.time);
  }

  /// One-time alertness-test reminder for tomorrow morning.
  Future<void> scheduleAlertnessReminder(DateTime at) =>
      _schedule(alertnessId, at, 'Take the 1-minute alertness test', 'See how sharp you are this morning.', _alertness,
          payload: 'alertness');

  /// Weekly-report-ready notification: Mondays at 09:00.
  Future<void> scheduleWeeklyReport(bool on) async {
    await cancel(weeklyId);
    if (!on) return;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, 9).add(Duration(days: (DateTime.monday - now.weekday) % 7));
    if (!at.isAfter(now)) at = at.add(const Duration(days: 7));
    await _schedule(weeklyId, at, 'Weekly report', 'Last week\'s summary is ready in your journal.', _weekly,
        payload: 'weekly', repeat: DateTimeComponents.dayOfWeekAndTime);
  }

  /// Two days before a 7-day trial ends.
  Future<void> scheduleTrialReminder(DateTime trialStart, {int days = 7}) => _schedule(
      trialId,
      trialStart.add(Duration(days: days - 2)),
      'Your free trial ends in 2 days',
      'Keep smart alarm, sounds and insights by staying on Premium, or cancel any time.',
      _trial,
      payload: 'premium');

  /// The sleep-aid player on the lock screen and in the shade: what's playing,
  /// with Pause/Play and Stop buttons.
  Future<void> showNowPlaying(String title, {required bool playing}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
          id: playerId,
          title: title,
          body: playing ? 'Sleep aid playing' : 'Sleep aid paused',
          payload: 'sleepaid',
          notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails('sleep_aid_player', 'Sleep aid player',
                  channelDescription: 'Controls for the sleep sound that\'s playing',
                  importance: Importance.low,
                  priority: Priority.low,
                  playSound: false,
                  enableVibration: false,
                  ongoing: playing,
                  autoCancel: false,
                  onlyAlertOnce: true,
                  showWhen: false,
                  category: AndroidNotificationCategory.transport,
                  visibility: NotificationVisibility.public,
                  actions: [
                    AndroidNotificationAction('aid_toggle', playing ? 'Pause' : 'Play', cancelNotification: false),
                    const AndroidNotificationAction('aid_stop', 'Stop', cancelNotification: true),
                  ])));
    } catch (_) {}
  }

  Future<void> showBatteryWarning(int percent) async {
    if (!_ready) return;
    try {
      await _plugin.show(
          id: batteryId,
          title: 'Battery low ($percent%)',
          body: 'Plug in your phone so tracking and your alarm keep running.',
          notificationDetails: const NotificationDetails(android: _battery));
    } catch (_) {}
  }
}

extension on AndroidNotificationDetails {
  /// FLAG_INSISTENT (4): the backup alarm repeats its sound until handled.
  AndroidNotificationDetails copyWithFlags() => AndroidNotificationDetails(channelId, channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      category: category,
      fullScreenIntent: fullScreenIntent,
      audioAttributesUsage: audioAttributesUsage,
      sound: sound,
      ongoing: ongoing,
      autoCancel: autoCancel,
      visibility: visibility,
      additionalFlags: Int32List.fromList([4]));
}
