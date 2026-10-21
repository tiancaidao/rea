import 'package:health/health.dart';
import '../data/models.dart';

/// Health Connect (Android) / HealthKit (iOS): read yesterday's steps for the
/// Journal, and write each night back as a sleep session when the user has
/// turned the integration on (Profile › More › Health Connect).
class HealthConnect {
  HealthConnect._();
  static final HealthConnect I = HealthConnect._();

  final Health _h = Health();
  bool _configured = false;

  static const _read = [HealthDataType.STEPS];
  static const _write = [HealthDataType.SLEEP_SESSION];

  Future<bool> _setup() async {
    if (!_configured) {
      await _h.configure();
      _configured = true;
    }
    return true;
  }

  /// Ask for permissions; false if Health Connect is missing or the user says no.
  Future<bool> connect() async {
    try {
      await _setup();
      final status = await _h.getHealthConnectSdkStatus();
      if (status != null && status != HealthConnectSdkStatus.sdkAvailable) return false;
      return await _h.requestAuthorization([..._read, ..._write],
          permissions: [HealthDataAccess.READ, HealthDataAccess.READ_WRITE]);
    } catch (_) {
      return false;
    }
  }

  /// Steps on the day before [wokeUp]; null when unavailable.
  Future<int?> stepsBefore(DateTime wokeUp) async {
    try {
      await _setup();
      final day = DateTime(wokeUp.year, wokeUp.month, wokeUp.day);
      if (await _h.hasPermissions(_read) != true) return null;
      return await _h.getTotalStepsInInterval(day.subtract(const Duration(days: 1)), day);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSleep(SleepSession s) async {
    try {
      await _setup();
      if (await _h.hasPermissions(_write, permissions: [HealthDataAccess.READ_WRITE]) != true) return;
      await _h.writeHealthData(
        value: s.minutesAsleep.toDouble(),
        type: HealthDataType.SLEEP_SESSION,
        startTime: s.startedAt,
        endTime: s.endedAt,
      );
    } catch (_) {}
  }
}
