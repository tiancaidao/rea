// Health integration: write sleep sessions to Apple HealthKit (iOS) and Health
// Connect (Android). Wraps the `health` package behind a tiny interface so the
// rest of the app doesn't depend on it. Add `health: ^10.0.0` to pubspec and
// uncomment the implementation once the platform permissions are configured
// (HealthKit capability on iOS, Health Connect on Android).

import 'models.dart';

abstract class HealthSync {
  Future<bool> requestPermissions();
  Future<void> writeSleepSession(SleepSession s);
}

/// No-op implementation so the app runs before Health is wired up.
class NoopHealthSync implements HealthSync {
  @override
  Future<bool> requestPermissions() async => false;
  @override
  Future<void> writeSleepSession(SleepSession s) async {}
}

/*
// Real implementation (enable after adding the `health` package + platform setup):
import 'package:health/health.dart';

class RealHealthSync implements HealthSync {
  final Health _health = Health();
  static const _types = [HealthDataType.SLEEP_SESSION];

  @override
  Future<bool> requestPermissions() =>
      _health.requestAuthorization(_types, permissions: [HealthDataAccess.READ_WRITE]);

  @override
  Future<void> writeSleepSession(SleepSession s) async {
    await _health.writeHealthData(
      value: s.minutesAsleep.toDouble(),
      type: HealthDataType.SLEEP_SESSION,
      startTime: s.startedAt,
      endTime: s.endedAt,
    );
  }
}
*/
