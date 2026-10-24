import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';
import '../app_state.dart';
import 'custom_song.dart';
import '../ui/settings_pages.dart' show AlarmSoundPage;

/// Plays the wake-up alarm: the chosen alarm sound, looping, fading in from a
/// whisper over the first minute (a gentle wake, as the original's melodies),
/// with vibration per Profile › More › Vibration:
///
/// * "As backup": the sound alone first; vibration joins after 45 s if the
///   alarm is still ringing.
/// * "Only vibration": a silent alarm.
/// * "Never": sound only.
class AlarmRinger {
  AlarmRinger._();
  static final AlarmRinger I = AlarmRinger._();

  // alarm stream, not media: rings at alarm volume even when media is muted
  final AudioPlayer _player = AudioPlayer(androidApplyAudioAttributes: false, handleInterruptions: false);
  Timer? _ramp, _vibrateLater;
  bool ringing = false;

  static const _rampTime = Duration(seconds: 60);
  static const _backupVibrationAfter = Duration(seconds: 45);
  static const _silentBackupAfter = Duration(minutes: 2);

  /// [silent]: the watch wakes you by vibrating; the phone joins in only
  /// if the alarm is still ringing after two minutes.
  Future<void> start({bool silent = false}) async {
    if (ringing) return;
    ringing = true;
    final s = AppState.I;
    await s.pauseSleepAid();
    if (silent) {
      _vibrateLater = Timer(_silentBackupAfter, () {
        if (ringing) unawaited(_playSound(s.pref('alarm_sound')));
      });
      return;
    }
    final vibration = s.pref('vibration');
    if (vibration != 'Only vibration') unawaited(_playSound(s.pref('alarm_sound')));
    if (vibration == 'Only vibration') {
      unawaited(_vibrate());
    } else if (vibration == 'As backup') {
      _vibrateLater = Timer(_backupVibrationAfter, () {
        if (ringing) _vibrate();
      });
    }
  }

  Future<void> _playSound(String name) async {
    final custom = name == CustomSong.label ? CustomSong.path : null;
    final file = custom ?? AlarmSoundPage.fileFor(name);
    if (file == null) return;
    try {
      await _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
          usage: AndroidAudioUsage.alarm, contentType: AndroidAudioContentType.sonification));
      await _player.setLoopMode(LoopMode.one);
      if (custom != null) {
        await _player.setFilePath(custom);
      } else {
        await _player.setAsset(file);
      }
      await _player.setVolume(0.08);
      unawaited(_player.play());
      final t0 = DateTime.now();
      _ramp = Timer.periodic(const Duration(seconds: 2), (t) {
        final f = DateTime.now().difference(t0).inMilliseconds / _rampTime.inMilliseconds;
        _player.setVolume((0.08 + 0.92 * f).clamp(0.08, 1.0));
        if (f >= 1) t.cancel();
      });
    } catch (_) {
      // no audio output in tests
    }
  }

  Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: const [0, 800, 600, 800, 600], repeat: 1);
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    ringing = false;
    _ramp?.cancel();
    _vibrateLater?.cancel();
    try {
      await _player.stop();
      await Vibration.cancel();
    } catch (_) {}
  }
}
