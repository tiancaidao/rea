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

  test('quiet epochs are asleep (deep appears), active epochs are awake', () {
    final still = List.generate(60, (_) => EpochFeatures(0.0));
    final labels = estimateStages(still);
    // mid-night quiet epochs are asleep (not awake) and deep sleep appears
    expect(labels.sublist(10, 50).contains('awake'), isFalse);
    expect(labels.contains('deep'), isTrue);
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

  test('snore detector bridges short gaps inside an episode only', () {
    const q = double.nan;
    final probs = <double>[0.9, 0.9, q, q, 0.9, 0.9, q, q, q, q, q, q, q, 0.9, 0.9, 0.9];
    final bridged = detectSnoreEvents(probs, maxGap: 5);
    expect(bridged.length, 2); // 0..5 joined across the 2-s gap; the 7-s gap splits
    expect(bridged.first.startFrame, 0);
    expect(bridged.first.endFrame, 6);
    expect(detectSnoreEvents(probs).length, 1); // without bridging only the last run is long enough
    // brief dips (not just quiet seconds) are bridged the same way
    final dips = <double>[0.9, 0.9, 0.9, 0.1, 0.1, 0.1, 0.9, 0.9, 0.9];
    expect(detectSnoreEvents(dips, majorityWindow: 1, maxGap: 5).length, 1);
    expect(detectSnoreEvents(dips, majorityWindow: 1).length, 2);
  });
}
