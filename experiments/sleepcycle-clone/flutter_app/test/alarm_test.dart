import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/alarm/alarm_plan.dart';
import 'package:sleep_tracker/data/night.dart';
import 'package:sleep_tracker/data/sound_clips.dart';
import 'package:sleep_tracker/theme.dart';
import 'package:sleep_tracker/ui/alarm_screen.dart';

void main() {
  group('AlarmPlan', () {
    final now = DateTime(2026, 10, 22, 23, 0);

    test('an alarm time that already passed rings tomorrow', () {
      final p = AlarmPlan.next(now, hour: 7, minute: 0, mode: 0, windowMinutes: 30, snooze: 'Regular');
      expect(p.end, DateTime(2026, 10, 23, 7, 0));
      expect(p.windowStart, DateTime(2026, 10, 23, 6, 30));
    });

    test('regular alarm rings exactly at the time; no alarm never rings', () {
      final p = AlarmPlan.next(now, hour: 7, minute: 0, mode: 1, windowMinutes: 30, snooze: 'Regular');
      expect(p.shouldRing(DateTime(2026, 10, 23, 6, 59), recentMovement: 1, nightMovement: List.filled(800, 0.1)),
          isFalse);
      expect(p.shouldRing(DateTime(2026, 10, 23, 7, 0)), isTrue);
      final off = AlarmPlan.next(now, hour: 7, minute: 0, mode: 2, windowMinutes: 30, snooze: 'Regular');
      expect(off.shouldRing(DateTime(2026, 10, 23, 9, 0)), isFalse);
    });

    test('smart alarm rings early on movement inside the window only', () {
      final p = AlarmPlan.next(now, hour: 7, minute: 0, mode: 0, windowMinutes: 30, snooze: 'Regular');
      final night = [for (var i = 0; i < 800; i++) i % 10 == 0 ? 0.8 : 0.05];
      // a restless moment before the window does nothing
      expect(p.shouldRing(DateTime(2026, 10, 23, 6, 20), recentMovement: 0.9, nightMovement: night), isFalse);
      // stillness inside the window: keep sleeping
      expect(p.shouldRing(DateTime(2026, 10, 23, 6, 35), recentMovement: 0.02, nightMovement: night), isFalse);
      // light sleep (movement) inside the window: wake now
      expect(p.shouldRing(DateTime(2026, 10, 23, 6, 35), recentMovement: 0.9, nightMovement: night), isTrue);
      // and always at the end
      expect(p.shouldRing(DateTime(2026, 10, 23, 7, 0), recentMovement: 0, nightMovement: night), isTrue);
    });

    test('smart snooze halves the time left, regular is 9 minutes', () {
      final smart =
          AlarmPlan(mode: 0, end: DateTime(2026, 10, 23, 7, 0), windowMinutes: 30, snooze: 'Smart (recommended)');
      expect(smart.snoozeFor(DateTime(2026, 10, 23, 6, 50)), const Duration(minutes: 5));
      expect(smart.snoozeFor(DateTime(2026, 10, 23, 6, 30)), const Duration(minutes: 9)); // capped
      expect(smart.snoozeFor(DateTime(2026, 10, 23, 6, 59)), const Duration(minutes: 5)); // past/at the end
      final regular = AlarmPlan(mode: 0, end: DateTime(2026, 10, 23, 7, 0), windowMinutes: 30, snooze: 'Regular');
      expect(regular.snoozeFor(DateTime(2026, 10, 23, 6, 50)), const Duration(minutes: 9));
      expect(AlarmPlan(mode: 1, end: DateTime(2026), windowMinutes: 0, snooze: 'Off').canSnooze, isFalse);
    });
  });

  testWidgets('alarm screen snoozes and shows when it rings again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final plan = AlarmPlan(mode: 1, end: DateTime.now(), windowMinutes: 0, snooze: 'Regular');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(AppThemeId.midnight.palette), home: AlarmScreen(plan: plan)));
    expect(find.text('Good morning'), findsOneWidget);
    await tester.tap(find.text('Snooze'));
    await tester.pump();
    expect(find.text('Snoozing'), findsOneWidget);
    expect(find.textContaining('Alarm rings again at'), findsOneWidget);
    expect(find.text('Snooze'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // dispose timers
  });

  test('sound clips are written as playable WAV and survive the night JSON', () async {
    final dir = await Directory.systemTemp.createTemp('clips');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/a.wav';
    await writeWav(path, Int16List.fromList(List.generate(16000, (i) => (i % 100) * 100)), 16000);
    final bytes = await File(path).readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(bytes.length, 44 + 32000);

    final n = Night.sample(DateTime(2026, 10, 22, 7), 3)
      ..clips.add(SoundClip(offsetSec: 120, path: path, kind: 'snore', peakDb: 21, durationMs: 6000))
      ..snoreSpans = [(100, 160)];
    final back = Night.fromJson(n.toJson());
    expect(back.clips.single.kind, 'snore');
    expect(back.snoreSpans, [(100, 160)]);
    expect(back.lightLux, n.lightLux);

    // keep only the newest night's clips
    await pruneClipFiles([back.clips, <SoundClip>[]], 1);
    expect(File(path).existsSync(), isFalse);
    expect(keepNightsFor('20 nights (recommended)'), 20);
    expect(keepNightsFor('Forever'), isNull);
    expect(keepNightsFor('0 nights'), 0);
  });

  test('alertness score rewards fast, accurate mornings', () {
    final fast = AlertnessResult(reactionMs: 300, accuracy: 1, at: DateTime(2026));
    final slow = AlertnessResult(reactionMs: 550, accuracy: 0.8, at: DateTime(2026));
    expect(fast.score, greaterThan(slow.score));
    expect(AlertnessResult.fromJson(fast.toJson()).reactionMs, 300);
  });
}
