// Real accelerometer source backed by a native platform channel.
// Native sides: android/.../SensingPlugin.kt and ios/.../SensingPlugin.swift.
//
// The native code runs a foreground/background service that samples the
// accelerometer (and, in a full build, the microphone) overnight and streams
// (x, y, z) in m/s^2 over an EventChannel. This keeps the heavy, platform-
// specific sensing native while all analysis stays in shared Dart.

import 'sleep_tracker.dart';
import 'package:flutter/services.dart';

class NativeAccelerometerSource implements AccelerometerSource {
  static const _events = EventChannel('sleepclone/accelerometer');
  static const _control = MethodChannel('sleepclone/sensing');

  /// Ask the native side to start the background sensing service.
  static Future<void> startService({int sampleHz = 50}) =>
      _control.invokeMethod('start', {'sampleHz': sampleHz});

  static Future<void> stopService() => _control.invokeMethod('stop');

  @override
  Stream<List<double>> samples() {
    return _events.receiveBroadcastStream().map((e) {
      final l = (e as List).cast<num>();
      return [l[0].toDouble(), l[1].toDouble(), l[2].toDouble()];
    });
  }
}
