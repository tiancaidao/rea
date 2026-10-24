import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/night.dart';
import '../device/notifications.dart';
import '../theme.dart';
import 'alertness_game.dart';
import 'widgets/common.dart';

/// After the alarm is stopped: the wake-up mood prompt (when Wake up mood is
/// on), then the offer to take the one-minute alertness test.
Future<void> runMorningFlow(BuildContext context, Night night) async {
  final s = AppState.I;
  if (s.pref('wake_up_mood') == 'Show' && night.mood == null) {
    await showWakeUpMoodSheet(context, night);
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => MorningSummary(night: night)));
  if (!context.mounted || !alertnessAvailable(night)) return;
  final play = await showModalBottomSheet<bool>(
    context: context,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bolt, size: 44, color: c.palette.warn),
        const SizedBox(height: 12),
        const Text('How sharp are you today?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
            'Play the one-minute alertness game. It works best within ${AppState.alertnessWindow.inHours} hours of waking up.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.palette.textMuted, height: 1.4)),
        const SizedBox(height: 24),
        PillButton('Play now', width: 220, onPressed: () => Navigator.pop(c, true)),
        TextButton(
          onPressed: () {
            Notifications.I.scheduleAlertnessReminder(DateTime.now().add(const Duration(minutes: 30)));
            Navigator.pop(c, false);
          },
          child: Text('Remind me in 30 minutes', style: TextStyle(color: c.palette.accent)),
        ),
      ]),
    ),
  );
  if (play == true && context.mounted) push(context, AlertnessGame(night: night));
}

/// "How do you feel?" with three faces; saves on the night.
Future<void> showWakeUpMoodSheet(BuildContext context, Night night) => showModalBottomSheet(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('How do you feel this morning?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 3; i++)
              GestureDetector(
                onTap: () {
                  night.mood = i;
                  AppState.I.nightChanged(night);
                  Navigator.pop(c);
                },
                child: Column(children: [
                  SizedBox(width: 64, height: 64, child: CustomPaint(painter: MoodFacePainter(i, c.palette.accent))),
                  const SizedBox(height: 6),
                  Text(moodLabels[i]),
                ]),
              ),
          ]),
        ]),
      ),
    );

const moodLabels = ['Bad', 'Okay', 'Good'];

/// A line-drawn face: frown, flat or smile.
class MoodFacePainter extends CustomPainter {
  final int mood;
  final Color color;
  MoodFacePainter(this.mood, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.44, p);
    canvas.drawCircle(Offset(w * 0.36, h * 0.4), w * 0.03, p);
    canvas.drawCircle(Offset(w * 0.64, h * 0.4), w * 0.03, p);
    final mouth = Path()..moveTo(w * 0.32, h * 0.66);
    final bend = [-0.12, 0.0, 0.12][mood];
    mouth.quadraticBezierTo(w * 0.5, h * (0.66 + bend), w * 0.68, h * 0.66);
    canvas.drawPath(mouth, p);
  }

  @override
  bool shouldRepaint(MoodFacePainter o) => o.mood != mood || o.color != color;
}

/// Weather art for a WMO code: an icon and the sky behind it.
(IconData, List<Color>, String) weatherArt(int? code, DateTime at) {
  final day = at.hour >= 6 && at.hour < 19;
  final clear = day ? const [Color(0xFF3A7BD5), Color(0xFF8EC5FC)] : const [Color(0xFF0F2027), Color(0xFF2C5364)];
  const grey = [Color(0xFF4B5563), Color(0xFF9CA3AF)];
  const storm = [Color(0xFF1F2937), Color(0xFF4B5563)];
  return switch (code) {
    null => (day ? Icons.wb_twilight : Icons.nights_stay, clear, ''),
    0 || 1 => (day ? Icons.wb_sunny : Icons.nightlight_round, clear, code == 0 ? 'Clear' : 'Mainly clear'),
    2 => (day ? Icons.wb_cloudy : Icons.cloud, clear, 'Partly cloudy'),
    3 => (Icons.cloud, grey, 'Overcast'),
    45 || 48 => (Icons.foggy, grey, 'Fog'),
    >= 51 && <= 67 || >= 80 && <= 82 => (Icons.water_drop, grey, 'Rain'),
    >= 71 && <= 77 || 85 || 86 => (Icons.ac_unit, grey, 'Snow'),
    >= 95 => (Icons.thunderstorm, storm, 'Thunderstorm'),
    _ => (Icons.cloud, grey, ''),
  };
}

/// "Good morning": the night at a glance over the morning's weather, shown
/// once after the alarm (before the alertness offer).
class MorningSummary extends StatelessWidget {
  final Night night;
  const MorningSummary({super.key, required this.night});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (icon, sky, label) = weatherArt(night.weatherCode, now);
    final greeting = now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
    final temp = night.weatherF == null ? null : '${night.weatherF}°F';
    Widget stat(String v, String k) => Column(children: [
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(k, style: const TextStyle(color: Colors.white70)),
        ]);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(children: [
              Text(greeting,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(fmtDt(now), style: const TextStyle(color: Colors.white70, fontSize: 18)),
              const Spacer(),
              Icon(icon, size: 120, color: Colors.white),
              const SizedBox(height: 12),
              if (temp != null || label.isNotEmpty)
                Text([if (temp != null) temp, if (label.isNotEmpty) label].join(' · '),
                    style: const TextStyle(color: Colors.white, fontSize: 20)),
              const Spacer(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                stat('${night.quality}%', 'Sleep quality'),
                stat(fmtDuration(night.asleepMinutes), 'Time asleep'),
                stat(fmtDt(night.wentToBed), 'Went to bed'),
              ]),
              const SizedBox(height: 40),
              PillButton('See my night', width: 240, onPressed: () => Navigator.pop(context)),
            ]),
          ),
        ),
      ),
    );
  }
}
