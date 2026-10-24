import 'package:health/health.dart';
import '../data/models.dart';
import '../sensing/sleep_tracker.dart';

/// Health Connect (Android) / HealthKit (iOS): read yesterday's steps for the
/// Journal, and write each night back as a sleep session when the user has
/// turned the integration on (Profile › More › Health Connect).
class HealthConnect {
  HealthConnect._();
  static final HealthConnect I = HealthConnect._();

  final Health _h = Health();
  bool _configured = false;

  static const _read = [HealthDataType.STEPS];
  static const _stages = {
    HealthDataType.SLEEP_DEEP: 'deep',
    HealthDataType.SLEEP_LIGHT: 'light',
    HealthDataType.SLEEP_REM: 'rem',
    HealthDataType.SLEEP_AWAKE: 'awake',
  };
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
      return await _h.requestAuthorization([..._read, ..._write, ..._stages.keys],
          permissions: [
            HealthDataAccess.READ,
            HealthDataAccess.READ_WRITE,
            for (final _ in _stages.keys) HealthDataAccess.READ,
          ]);
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

  /// Sleep sessions other apps (a watch, another tracker) wrote in the last
  /// [days] days, with their stages mapped onto 30-second epochs. Sessions
  /// without stages count as light sleep. Empty when unavailable.
  Future<List<SleepSession>> importSleep({int days = 30}) async {
    try {
      await _setup();
      final now = DateTime.now();
      final from = now.subtract(Duration(days: days));
      final types = [HealthDataType.SLEEP_SESSION, ..._stages.keys];
      final points = await _h.getHealthDataFromTypes(types: types, startTime: from, endTime: now);
      final sessions = points.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();
      final out = <SleepSession>[];
      for (final s in sessions) {
        final epochs = s.dateTo.difference(s.dateFrom).inSeconds ~/ 30;
        if (epochs < 120) continue; // under an hour: a nap, skip
        final labels = List.filled(epochs, 'light');
        for (final p in points.where((p) => _stages.containsKey(p.type))) {
          final a = p.dateFrom.difference(s.dateFrom).inSeconds ~/ 30;
          final b = p.dateTo.difference(s.dateFrom).inSeconds ~/ 30;
          for (var i = a.clamp(0, epochs); i < b.clamp(0, epochs); i++) {
            labels[i] = _stages[p.type]!;
          }
        }
        out.add(SleepSession(
          startedAt: s.dateFrom,
          endedAt: s.dateTo,
          phases: [for (var i = 0; i < epochs; i++) PhasePoint(i, labels[i])],
          snoreEvents: 0,
          snorePercent: 0,
          sleepScore: SleepTracker.scoreFor(labels),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
