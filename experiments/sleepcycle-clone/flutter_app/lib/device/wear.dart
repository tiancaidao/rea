import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Wear OS companion (android/wear), over the Wearable Data Layer.
///
/// The phone stays the device that tracks and decides when to wake you; the
/// watch is a remote: start and stop the night, snooze or stop the alarm,
/// wake silently by vibration, and the Snore Alert nudge. Watch requests
/// arrive on [requests]; the phone publishes its state with [publish].
class Wear {
  Wear._();
  static final Wear I = Wear._();

  static const _method = MethodChannel('sleepclone/wear');
  static const _events = EventChannel('sleepclone/wear/events');

  /// start · stop · snooze · stop_alarm · sync · alarm_type:<value> · snore_ack
  final StreamController<String> _requests = StreamController.broadcast();
  Stream<String> get requests => _requests.stream;

  /// Whether a watch with the app is connected right now.
  final ValueNotifier<bool> connected = ValueNotifier(false);

  bool _started = false;

  void init() {
    if (_started || defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    _started = true;
    try {
      _events.receiveBroadcastStream().listen((e) => _requests.add(e as String), onError: (_) {});
    } catch (_) {}
    unawaited(refresh());
  }

  Future<void> refresh() async {
    connected.value = await _call<bool>('connected') ?? false;
  }

  /// Phone state for the watch's main screen.
  Future<void> publish({
    required bool tracking,
    DateTime? since,
    DateTime? alarmStart,
    DateTime? alarmEnd,
    required String alarmType,
  }) =>
      _call('publish', {
        'tracking': tracking,
        'since': since?.millisecondsSinceEpoch ?? 0,
        'alarmStart': alarmStart?.millisecondsSinceEpoch ?? 0,
        'alarmEnd': alarmEnd?.millisecondsSinceEpoch ?? 0,
        'alarmType': alarmType,
      });

  /// Ring on the watch: [vibrate] silently, else alongside the phone's melody.
  Future<void> ring({required bool vibrate}) => _call('ring', {'vibrate': vibrate});

  Future<void> stopRinging() => _call('stopRinging');

  /// Snore Alert: a short buzz on the wrist to nudge a change of position.
  Future<void> buzzSnore() => _call('buzzSnore');

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!_started) return null;
    try {
      return await _method.invokeMethod<T>(method, args);
    } catch (_) {
      return null; // no Play services / no watch
    }
  }

  /// Whether to wake by vibrating the watch, for the Watch › Alarm type
  /// setting: Automatic vibrates when the night was started from the watch.
  static bool vibrateFor(String alarmType, {required bool startedFromWatch}) => switch (alarmType) {
        'Vibrate' => true,
        'Melody' => false,
        _ => startedFromWatch,
      };
}
