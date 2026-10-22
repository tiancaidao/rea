import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process alive overnight with an ongoing "tracking" notification
/// (a microphone / health foreground service on Android, as the original's
/// sleep-analysis service), so sensing and the in-app alarm keep running with
/// the screen off. The sensing itself stays in the main isolate; the task
/// handler only exists because the service needs one.
class TrackingService {
  static bool _inited = false;

  static void _init() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tracking',
        channelName: 'Sleep tracking',
        channelDescription: 'Shown while your night is being tracked',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> start(String alarmText, {required bool microphone}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      _init();
      if (await FlutterForegroundTask.isRunningService) {
        await update(alarmText);
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 4242,
        serviceTypes: [
          if (microphone) ForegroundServiceTypes.microphone,
          ForegroundServiceTypes.health,
        ],
        notificationTitle: 'Sleep tracking is on',
        notificationText: alarmText,
        callback: _startCallback,
      );
    } catch (_) {
      // no service (tests, permission missing): tracking still runs while visible
    }
  }

  static Future<void> update(String text) async {
    try {
      await FlutterForegroundTask.updateService(notificationTitle: 'Sleep tracking is on', notificationText: text);
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void _startCallback() => FlutterForegroundTask.setTaskHandler(_KeepAlive());

class _KeepAlive extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
