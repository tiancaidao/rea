import 'dart:async';
import 'package:flutter/services.dart';

/// Battery level and the ambient light sensor, over the small native
/// `DevicePlugin` (android/.../DevicePlugin.kt). Both degrade to null where
/// the platform side is missing (tests, iOS without a light sensor API).
class DeviceSensors {
  static const _method = MethodChannel('sleepclone/device');
  static const _light = EventChannel('sleepclone/light');

  /// (percent 0..100, charging) or null when unknown.
  static Future<(int, bool)?> battery() async {
    try {
      final m = await _method.invokeMapMethod<String, dynamic>('battery');
      if (m == null) return null;
      return ((m['level'] as num).toInt(), m['charging'] == true);
    } catch (_) {
      return null;
    }
  }

  /// Illuminance in lux, roughly a few readings per second while listened to.
  /// Empty stream when the device has no light sensor.
  static Stream<double> light() {
    try {
      return _light.receiveBroadcastStream().map((e) => (e as num).toDouble()).handleError((_) {});
    } catch (_) {
      return const Stream.empty();
    }
  }
}

/// Lets the ringing alarm show over the lock screen (Android), off otherwise.
Future<void> showOverLockScreen(bool on) async {
  try {
    await const MethodChannel('sleepclone/window').invokeMethod('showOverLock', {'on': on});
  } catch (_) {}
}
