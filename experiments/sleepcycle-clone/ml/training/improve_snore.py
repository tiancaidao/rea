"""
Improvements pass for the snore / sound-event model: try each idea, keep what helps.

Each variant runs train_snore.py --val-only (train split only, epoch and threshold
picked on val, metrics on val). Score = 0.5 * val snore average precision +
0.5 * val F0.5 at the val-chosen threshold (precision-weighted, since false alarms
matter most). Ideas that help on val are combined. The final configuration is then
trained the normal way (refit on train+val), and test is scored once.

Uses the open data plus APSAA (accepted by Ray, research-only); val and test
include held-out APSAA patients.

  python3 training/improve_snore.py            # ablation -> data/improve_snore.json
  python3 training/improve_snore.py --final    # also train + export the chosen config
"""
from __future__ import annotations
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
OUT = os.path.join(HERE, "..", "data", "improve_snore.json")

TRIALS = [
    ("baseline (shipped config)", {}),
    ("aug: room reverb", dict(aug_reverb=True)),
    ("aug: phone-mic band-limits 3-6 kHz", dict(aug_lowpass=True)),
    ("aug: ±10% time stretch", dict(aug_stretch=True)),
    ("aug: ±2-band pitch shift", dict(aug_pitch=True)),
    ("hard negatives: clock / breathing / pets drawn 3x", dict(hardneg=3.0)),
    ("loss: focal, gamma 2", dict(focal=2.0)),
    ("loss: no label smoothing", dict(label_smoothing=0.0)),
    ("arch: wider (24/48/96)", dict(widths=[24, 48, 96])),
    ("arch: deeper (16/32/64/64)", dict(widths=[16, 32, 64, 64])),
]


def run(cfg, extra=("--val-only", "--no-export")):
    env = {**os.environ, "SNORE_CFG": json.dumps(cfg)}
    out = subprocess.run([PY, "-I", os.path.join(HERE, "train_snore.py"), *extra],
                         env=env, capture_output=True, text=True)
    for line in out.stdout.splitlines():
        if line.startswith("VAL_RESULT "):
            return json.loads(line[len("VAL_RESULT "):])
    if "--val-only" in extra:
        raise RuntimeError(out.stdout[-2000:] + out.stderr[-2000:])
    return out.stdout


def score(r):
    return 0.5 * r["snore_ap"] + 0.5 * r["f05"]


def main():
    rows = []
    for name, delta in TRIALS:
        r = run(delta)
        rows.append((name, delta, r))
        print(f"{name:52s} AP {r['snore_ap']:.3f}  P {r['precision']:.2f} R {r['recall']:.2f} F0.5 {r['f05']:.3f} "
              f"macroF1 {r['macro_f1']:.3f} score {score(r):.3f} ({score(r) - score(rows[0][2]):+.3f})", flush=True)
    base = score(rows[0][2])
    kept = [d for n, d, r in rows[1:] if score(r) - base > 0.01]
    combo = {}
    for d in kept:
        combo.update(d)
    rc = run(combo) if len(kept) > 1 else None
    best_single = max(rows, key=lambda x: score(x[2]))
    if rc is not None and score(rc) >= score(best_single[2]):
        final_cfg, final_val = combo, rc
    else:
        final_cfg, final_val = best_single[1], best_single[2]
    print("kept:", kept, "| combined:", None if rc is None else round(score(rc), 3), "| final:", final_cfg)
    json.dump(dict(rows=rows, kept=kept, combo=combo, combo_val=rc, final_cfg=final_cfg, final_val=final_val),
              open(OUT, "w"), indent=1)
    if "--final" in sys.argv:
        print(run(final_cfg, extra=())[-1500:])


if __name__ == "__main__":
    main()
