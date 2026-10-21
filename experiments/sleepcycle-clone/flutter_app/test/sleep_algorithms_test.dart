import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_tracker/core/sleep_algorithms.dart';

void main() {
  test('movement aggregator emits one value per epoch', () {
    final cfg = MovementConfig(sampleHz: 10, epochSeconds: 2); // 20 samples/epoch
    final agg = MovementAggregator(cfg);
    final emitted = <double>[];
    for (var i = 0; i < 60; i++) {
      final jolt = (i == 25 || i == 45) ? 2.0 : 0.0;
      final out = agg.addSample(jolt, 0, gravity);
      if (out != null) emitted.add(out);
    }
    expect(emitted.length, 3);
  });

  test('still epochs are deep, active epochs are awake', () {
    final still = List.generate(20, (_) => EpochFeatures(0.0));
    expect(estimateStages(still).take(10).toSet(), {'deep'});
    final active = List.generate(20, (_) => EpochFeatures(1.0));
    expect(estimateStages(active).first, 'awake');
  });

  test('stage tail is forced awake', () {
    final epochs = List.generate(20, (_) => EpochFeatures(0.0));
    final labels = estimateStages(epochs, tailAwakeEpochs: 6);
    expect(labels.sublist(labels.length - 6), List.filled(6, 'awake'));
  });

  test('smart alarm fires at window end and on a big move', () {
    final sa = SmartAlarm(windowMinutes: 30);
    final night = List.generate(400, (i) => (i % 17) / 17.0);
    expect(sa.shouldFire(30, 0, night), isTrue);
    expect(sa.shouldFire(0, 99, night), isTrue);
    expect(sa.shouldFire(0, 0, night), isFalse);
  });

  test('snore detector rejects blips, keeps real runs', () {
    final probs = <double>[0.9, 0, 0, 0, 0, 0, 0.9, 0.95, 0.92, 0.9, 0, 0, 0, 0, 0];
    final events = detectSnoreEvents(probs);
    expect(events.length, 1);
    expect(events.first.endFrame - events.first.startFrame, greaterThanOrEqualTo(3));
  });
}
