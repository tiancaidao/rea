"""
Tests + runnable demo for sleep_core. Run: python3 test_sleep_core.py
(no third-party deps).
"""
import random
from movement import MovementAggregator, MovementConfig, GRAVITY, calibrate_threshold
from sleep_stages import EpochFeatures, estimate_stages
from smart_alarm import SmartAlarm
from snore import SnoreEventConfig, detect_events, who_is_snoring


def test_movement_emits_one_value_per_epoch():
    cfg = MovementConfig(sample_hz=10, epoch_seconds=2)  # 20 samples/epoch
    agg = MovementAggregator(cfg)
    emitted = []
    for i in range(60):  # 3 epochs
        # mostly still with gravity on z, a couple of jolts
        jolt = 2.0 if i in (25, 45) else 0.0
        out = agg.add_sample(jolt, 0.0, GRAVITY)
        if out:
            emitted.append(out)
    assert [e[0] for e in emitted] == [0, 1, 2], emitted
    assert emitted[0][1] >= 0.0


def test_calibrate_threshold_floor():
    assert calibrate_threshold([], ) == MovementConfig().spike_threshold_g
    quiet = [1.0 + 0.001 * ((-1) ** i) for i in range(50)]
    assert calibrate_threshold(quiet) >= 0.005


def test_stages_still_is_deep_active_is_awake():
    still = [EpochFeatures(movement=0.0) for _ in range(20)]
    assert set(estimate_stages(still)[:10]) == {"deep"}
    active = [EpochFeatures(movement=1.0) for _ in range(20)]
    assert estimate_stages(active)[0] == "awake"


def test_stages_force_tail_awake():
    epochs = [EpochFeatures(movement=0.0) for _ in range(20)]
    labels = estimate_stages(epochs, tail_awake_epochs=6)
    assert labels[-6:] == ["awake"] * 6


def test_smart_alarm_fires_at_window_end_and_on_big_move():
    sa = SmartAlarm(window_minutes=30)
    night = [random.random() for _ in range(400)]
    assert sa.should_fire(30, 0.0, night) is True            # end of window always fires
    assert sa.should_fire(0, max(night) + 1, night) is True  # huge stir fires immediately
    assert sa.should_fire(0, 0.0, night) is False            # dead still at window start: wait


def test_snore_events_reject_blips():
    cfg = SnoreEventConfig(min_event_frames=3, majority_window=3)
    probs = [0.9] + [0.0] * 5 + [0.9, 0.95, 0.92, 0.9] + [0.0] * 5   # one blip, one real run
    events = detect_events(probs, cfg)
    assert len(events) == 1
    assert events[0].end_frame - events[0].start_frame >= 3


def test_who_is_snoring_needs_enough_samples():
    emb = [1.0, 0.0, 0.0]
    assert who_is_snoring(emb, [], k=3) is None
    labelled = [([1.0, 0.0, 0.0], "me")] * 8 + [([0.0, 1.0, 0.0], "other")] * 4
    assert who_is_snoring(emb, labelled, k=3) == "me"


def _demo():
    random.seed(1)
    cfg = MovementConfig(sample_hz=10, epoch_seconds=30)
    agg = MovementAggregator(cfg)
    movements = []
    for minute in range(420):          # a 7h night, one "minute" loop
        restless = minute < 20 or minute > 400 or (120 < minute < 135)
        for _ in range(cfg.sample_hz * 60):
            amp = 0.4 if (restless and random.random() < 0.05) else 0.0
            out = agg.add_sample(random.gauss(0, amp), random.gauss(0, amp), GRAVITY)
            if out:
                movements.append(out[1])
    mx = max(movements) or 1.0
    feats = [EpochFeatures(movement=m / mx) for m in movements]
    stages = estimate_stages(feats)
    counts = {s: stages.count(s) for s in ("deep", "light", "rem", "awake")}
    print(f"demo night: {len(stages)} epochs ->", counts)
    sa = SmartAlarm(window_minutes=30)
    fired = next((i for i in range(30) if sa.should_fire(i, feats[-30 + i].movement, movements)), 30)
    print(f"smart alarm would fire {fired} min into the 30-min window")


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} tests passed\n")
    _demo()
