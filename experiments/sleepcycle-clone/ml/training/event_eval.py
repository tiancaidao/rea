"""
Event-level evaluation of the snore post-processing, on continuous APSAA audio.

The app turns one P(snore) per second into snore events with detectSnoreEvents
(flutter_app/lib/core/sleep_algorithms.dart). This script runs the exported
model over continuous 10-minute stretches of held-out APSAA patients, one
decision per second exactly like the app, and scores smoothing rules against
the technicians' snore annotations:

  * event precision / recall: a detected event is correct if it overlaps an
    annotated snore episode; an annotated episode is found if a detection overlaps it
  * false alarms per hour: detected events overlapping no annotation
  * snore-minutes error per stretch: |detected minutes - annotated minutes|

Rules are chosen on validation patients; test patients are scored once.
Research-only data (APSAA, accepted by Ray).

  python3 training/event_eval.py              # val: compare rules -> data/event_eval.json
  python3 training/event_eval.py --test RULE  # test once with the chosen rule
"""
from __future__ import annotations
import csv
import io
import json
import os
import sys
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
from audio_pipeline import SAMPLE_RATE, N_FRAMES, logmel_frames  # noqa: E402
from prepare_data import APSAA_ZIP, _apsaa_split  # noqa: E402

STRETCH_S, PER_PATIENT = 600, 3


def detect(p, thr, window=3, min_len=3, max_gap=0):
    """Python mirror of detectSnoreEvents (no NaN gating here): majority vote over
    `window` seconds, optional bridging, events >= min_len s with mean P >= thr."""
    n = len(p)
    half = window // 2
    on = np.array([(p[max(0, i - half):i + half + 1] >= thr).sum() * 2 > len(p[max(0, i - half):i + half + 1])
                   for i in range(n)])
    if max_gap:
        i = 0
        while i < n:
            if not on[i]:
                j = i
                while j < n and not on[j]:
                    j += 1
                if 0 < i and j < n and j - i <= max_gap:
                    on[i:j] = True
                i = j
            else:
                i += 1
    ev, start = [], None
    for i in range(n + 1):
        a = on[i] if i < n else False
        if a and start is None:
            start = i
        elif not a and start is not None:
            if i - start >= min_len and p[start:i].mean() >= thr:
                ev.append((start, i))
            start = None
    return ev


RULES = {
    "per-second threshold (no smoothing)": dict(window=1, min_len=1),
    "app: 3-s majority, >= 3 s": dict(window=3, min_len=3),
    "3-s majority, >= 3 s, bridge gaps <= 5 s": dict(window=3, min_len=3, max_gap=5),
    "5-s majority, >= 3 s": dict(window=5, min_len=3),
    "5-s majority, >= 5 s, bridge gaps <= 5 s": dict(window=5, min_len=5, max_gap=5),
    "3-s majority, >= 5 s, bridge gaps <= 10 s": dict(window=3, min_len=5, max_gap=10),
}


def stretches(split_name, rng):
    import onnxruntime as ort
    from scipy.signal import resample_poly
    sess = ort.InferenceSession(os.path.join(HERE, "snore_classifier.onnx"), providers=["CPUExecutionProvider"])
    norm = np.load(os.path.join(HERE, "snore_norm.npz"))
    mean, std = float(norm["mean"]), float(norm["std"])
    z = zipfile.ZipFile(APSAA_ZIP)
    subjects = sorted({n.split("/")[0] for n in z.namelist() if n.endswith(".wav")})
    split = _apsaa_split(subjects)
    import soundfile as sf
    for sid in [s for s in subjects if split[s] == split_name]:
        rec, sr = sf.read(io.BytesIO(z.read(f"{sid}/{sid}.wav")), dtype="float32")
        ann = list(csv.DictReader(io.TextIOWrapper(z.open(f"{sid}/{sid}_Annotations.csv"))))
        secs = lambda t: sum(float(x) * m for x, m in zip(t.split(":"), (3600, 60, 1)))  # noqa: E731
        sn = [(secs(a["Start_Time"]), secs(a["Start_Time"]) + float(a["Duration"]))
              for a in ann if a["Event_Name"].strip().lower() == "snore"]
        dur = len(rec) / sr
        # stretches with some annotated snoring and ones without, as a night has both
        starts = rng.choice(np.arange(1800, dur - STRETCH_S - 1800, 60.0), PER_PATIENT, replace=False)
        for t0 in starts:
            up = resample_poly(rec[int(t0 * sr):int((t0 + STRETCH_S + 3) * sr)], 441, 40).astype(np.float32)
            lm = logmel_frames(up)
            n = STRETCH_S
            X = np.stack([lm[k * 43:k * 43 + N_FRAMES] for k in range(n)])[:, None]
            lo = sess.run(None, {"mel": ((X - mean) / std).astype(np.float32)})[0]
            p = np.exp(lo - lo.max(1, keepdims=True))
            p = (p / p.sum(1, keepdims=True))[:, 0]
            truth = [(max(0, s - t0), min(n, e - t0)) for s, e in sn if e > t0 and s < t0 + n]
            yield sid, p, truth


def score(data, thr, rule):
    tp_ev = fp_ev = found = total = 0
    err, hours = [], 0.0
    for _, p, truth in data:
        ev = detect(p, thr, **rule)
        ov = lambda a, b: a[0] < b[1] and b[0] < a[1]  # noqa: E731
        tp_ev += sum(1 for e in ev if any(ov(e, t) for t in truth))
        fp_ev += sum(1 for e in ev if not any(ov(e, t) for t in truth))
        found += sum(1 for t in truth if any(ov(e, t) for e in ev))
        total += len(truth)
        err.append(abs(sum(b - a for a, b in ev) - sum(b - a for a, b in truth)) / 60)
        hours += len(p) / 3600
    return dict(event_precision=tp_ev / max(1, tp_ev + fp_ev), event_recall=found / max(1, total),
                false_alarms_per_hour=fp_ev / hours, minutes_mae_per_10min=float(np.mean(err)),
                stretches=len(data), annotated_episodes=total)


def main():
    thr = float(np.load(os.path.join(HERE, "snore_norm.npz"))["threshold"])
    rng = np.random.default_rng(5)
    if "--test" in sys.argv:
        rule_name = sys.argv[sys.argv.index("--test") + 1]
        data = list(stretches("test", rng))
        r = score(data, thr, RULES[rule_name])
        print("TEST", rule_name, json.dumps(r))
        j = json.load(open(os.path.join(HERE, "..", "data", "event_eval.json")))
        j["test"] = {rule_name: r}
        json.dump(j, open(os.path.join(HERE, "..", "data", "event_eval.json"), "w"), indent=1)
        return
    data = list(stretches("val", rng))
    out = {}
    for name, rule in RULES.items():
        out[name] = score(data, thr, rule)
        r = out[name]
        print(f"{name:45s} event P {r['event_precision']:.2f} R {r['event_recall']:.2f} "
              f"FA/h {r['false_alarms_per_hour']:.1f} minutes MAE/10min {r['minutes_mae_per_10min']:.2f}")
    json.dump(dict(threshold=thr, val=out), open(os.path.join(HERE, "..", "data", "event_eval.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
