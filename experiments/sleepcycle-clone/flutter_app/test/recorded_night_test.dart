import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/data/recorded_night.dart';

void main() {
  // 8 hours of synthetic events in the recording format: quiet with a few
  // movements, plus one 10-minute snore episode (701 start / 702 stop).
  String csv() {
    const ns = 60000000000; // one minute
    final b = StringBuffer('eventType, timestamp, intensity\n');
    for (var m = 0; m <= 480; m += 3) {
      final restless = m < 20 || m > 470 || m % 90 > 80;
      b.writeln('1, ${m * ns}, ${restless ? 0.06 : 0.002}');
    }
    b.writeln('701, ${100 * ns}, 0.0');
    b.writeln('702, ${110 * ns}, 0.0');
    return b.toString();
  }

  test('parses movement and snore events', () {
    final r = RecordedNight.parse(csv())!;
    expect(r.minutes, 480);
    expect(r.snores.single.$2 - r.snores.single.$1, closeTo(10, 0.01));
    expect(r.movements, isNotEmpty);
  });

  test('replay builds a full night with all stages; jittered seeds differ', () {
    final r = RecordedNight.parse(csv())!;
    final woke = DateTime(2026, 10, 21, 7);
    final a = r.toNight(woke);
    expect(a.inBedMinutes, 480);
    expect(a.snoreMinutes, 10);
    final stages = a.session.phases.map((p) => p.phase).toSet();
    expect(stages.containsAll(['awake', 'light', 'deep', 'rem']), isTrue);
    final b = r.toNight(woke, seed: 7);
    expect(b.inBedMinutes == a.inBedMinutes && b.quality == a.quality, isFalse);
  });

  test('garbage input yields null', () {
    expect(RecordedNight.parse('nope'), isNull);
  });
}
