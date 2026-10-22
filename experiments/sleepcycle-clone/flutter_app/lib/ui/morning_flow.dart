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
