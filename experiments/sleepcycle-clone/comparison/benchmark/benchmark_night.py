#!/usr/bin/env python3
"""
Benchmark our tracker against the original app on the SAME nights.

The original app's CSV export (Profile > More > Database > Export) only grades
our output here. It is read, compared, and summarised into a report; it is never
written anywhere else and never used to train or tune a model.

Inputs
  --ours     our export: JSON list of nights (Settings > Database > "Export
             nights for benchmarking" -> sleep_export.json). Each night carries
             its per-30-s hypnogram, snore minutes and score.
  --theirs   the original app's CSV export. Header-driven: ';' or ',' delimited,
             known columns are matched by name (see THEIR_COLUMNS), unknown ones
             are listed in the report and ignored.
  --their-hypnogram  optional CSV `time,stage` (e.g. digitised from the night's
             graph) for epoch-level hypnogram agreement; stages awake / light /
             deep (REM optional).
  --reference-hypnogram  optional ground truth `time,stage` (e.g. a public PSG
             night, or a wearable) — then both apps are scored against it.

Nights are paired by time overlap (>= 50% of the shorter night). Metrics per
night and over all paired nights: bias (ours - theirs), MAE, Bland-Altman 95%
limits of agreement, Pearson r (n >= 3), and agreement on "snored > 5 min".
Hypnograms (when given): 30-s epoch accuracy, Cohen's kappa, confusion matrix,
3-class wake / light / deep (our REM folds into light, as the original's graph
shows awake / sleep / deep).

  python3 benchmark_night.py --ours sleep_export.json --theirs sleepdata.csv --out report.md
  python3 benchmark_night.py --selftest       # synthetic files, checks the harness end-to-end
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
import os
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta

EPOCH = 30  # seconds

# their column (lower-cased, as exported) -> our field. Matched exactly first,
# then by "contains" so small wording changes between app versions still map.
THEIR_COLUMNS = {
    "start": "start",
    "end": "end",
    "sleep quality": "quality",
    "time in bed (seconds)": "in_bed_s",
    "time asleep (seconds)": "asleep_s",
    "time before sleep (seconds)": "latency_s",
    "snore time (seconds)": "snore_s",
    "regularity": "regularity",
}
STAGE3 = {"awake": "wake", "wake": "wake", "w": "wake", "light": "light", "sleep": "light", "n1": "light",
          "n2": "light", "rem": "light", "dream": "light", "r": "light", "deep": "deep", "n3": "deep",
          "n4": "deep"}


@dataclass
class Night:
    start: datetime
    end: datetime
    quality: float | None = None
    in_bed_min: float | None = None
    asleep_min: float | None = None
    latency_min: float | None = None
    snore_min: float | None = None
    hypnogram: list[tuple[datetime, str]] = field(default_factory=list)  # (epoch start, stage3)


# --------------------------------------------------------------------------- parsing

def _dt(s: str) -> datetime:
    s = s.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%d/%m/%Y %H:%M:%S", "%m/%d/%Y %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d.replace(tzinfo=None) if d.tzinfo is None else d.astimezone().replace(tzinfo=None)


def _num(s: str | None) -> float | None:
    if s is None:
        return None
    s = s.strip().rstrip("%").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


def read_ours(path: str) -> list[Night]:
    nights = []
    for j in json.load(open(path)):
        s = j["session"]
        start = datetime.fromtimestamp(s["startedAt"] / 1000)
        end = datetime.fromtimestamp(s["endedAt"] / 1000)
        phases = sorted(s["phases"], key=lambda p: p["t"])
        hyp = [(start + timedelta(seconds=EPOCH * p["t"]), STAGE3[p["phase"]]) for p in phases]
        asleep = sum(1 for _, st in hyp if st != "wake") * EPOCH / 60
        first = next((i for i, (_, st) in enumerate(hyp) if st != "wake"), None)
        nights.append(Night(start, end, quality=s.get("sleepScore"), in_bed_min=(end - start).total_seconds() / 60,
                            asleep_min=asleep, latency_min=None if first is None else first * EPOCH / 60,
                            snore_min=j.get("snoreMinutes"), hypnogram=hyp))
    return nights


def read_theirs(path: str) -> tuple[list[Night], list[str]]:
    raw = open(path, encoding="utf-8-sig").read()
    delim = ";" if raw.splitlines()[0].count(";") > raw.splitlines()[0].count(",") else ","
    rows = list(csv.reader(io.StringIO(raw), delimiter=delim))
    header = [h.strip() for h in rows[0]]
    col, unknown = {}, []
    for i, h in enumerate(header):
        key = h.lower()
        field_ = THEIR_COLUMNS.get(key) or next((v for k, v in THEIR_COLUMNS.items() if k in key), None)
        if field_ and field_ not in col:
            col[field_] = i
        else:
            unknown.append(h)
    if "start" not in col or "end" not in col:
        raise SystemExit(f"{path}: need Start and End columns, got {header}")
    nights = []
    for r in rows[1:]:
        if len(r) < len(header) or not r[col["start"]].strip():
            continue
        g = lambda f: _num(r[col[f]]) if f in col else None  # noqa: E731
        nights.append(Night(_dt(r[col["start"]]), _dt(r[col["end"]]), quality=g("quality"),
                            in_bed_min=None if g("in_bed_s") is None else g("in_bed_s") / 60,
                            asleep_min=None if g("asleep_s") is None else g("asleep_s") / 60,
                            latency_min=None if g("latency_s") is None else g("latency_s") / 60,
                            snore_min=None if g("snore_s") is None else g("snore_s") / 60))
    return nights, unknown


def read_hypnogram(path: str) -> list[tuple[datetime, str]]:
    out = []
    for r in csv.DictReader(open(path)):
        st = STAGE3.get(r["stage"].strip().lower())
        if st:
            out.append((_dt(r["time"]), st))
    return sorted(out)


# --------------------------------------------------------------------------- comparison

def pair(ours: list[Night], theirs: list[Night]) -> list[tuple[Night, Night]]:
    pairs, used = [], set()
    for a in ours:
        best, best_ov = None, 0.0
        for k, b in enumerate(theirs):
            if k in used:
                continue
            ov = (min(a.end, b.end) - max(a.start, b.start)).total_seconds()
            shorter = min((a.end - a.start).total_seconds(), (b.end - b.start).total_seconds())
            if shorter > 0 and ov / shorter >= 0.5 and ov > best_ov:
                best, best_ov = k, ov
        if best is not None:
            used.add(best)
            pairs.append((a, theirs[best]))
    return pairs


def stats(xs: list[float], ys: list[float]) -> dict:
    d = [x - y for x, y in zip(xs, ys)]
    n = len(d)
    if n == 0:
        return {"n": 0}
    bias = sum(d) / n
    sd = math.sqrt(sum((v - bias) ** 2 for v in d) / (n - 1)) if n > 1 else 0.0
    out = {"n": n, "bias": bias, "mae": sum(abs(v) for v in d) / n, "loa": (bias - 1.96 * sd, bias + 1.96 * sd)}
    if n >= 3:
        mx, my = sum(xs) / n, sum(ys) / n
        sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
        sy = math.sqrt(sum((y - my) ** 2 for y in ys))
        out["r"] = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy) if sx and sy else float("nan")
    return out


def kappa(a: list[str], b: list[str], labels: list[str]) -> tuple[float, float, list[list[int]]]:
    idx = {l: i for i, l in enumerate(labels)}
    cm = [[0] * len(labels) for _ in labels]
    for x, y in zip(a, b):
        cm[idx[x]][idx[y]] += 1
    n = sum(map(sum, cm))
    if n == 0:
        return float("nan"), float("nan"), cm
    po = sum(cm[i][i] for i in range(len(labels))) / n
    pe = sum(sum(cm[i]) * sum(r[i] for r in cm) for i in range(len(labels))) / n ** 2
    return po, (po - pe) / (1 - pe) if pe < 1 else float("nan"), cm


def align(h1: list[tuple[datetime, str]], h2: list[tuple[datetime, str]]) -> tuple[list[str], list[str]]:
    """Stage at each 30-s epoch over the overlap of two step-function hypnograms."""
    if not h1 or not h2:
        return [], []
    t, t_end = max(h1[0][0], h2[0][0]), min(h1[-1][0], h2[-1][0]) + timedelta(seconds=EPOCH)

    def at(h, when):
        st = h[0][1]
        for ts, s in h:
            if ts > when:
                break
            st = s
        return st

    a, b = [], []
    while t < t_end:
        a.append(at(h1, t))
        b.append(at(h2, t))
        t += timedelta(seconds=EPOCH)
    return a, b


# --------------------------------------------------------------------------- report

METRICS = [("in_bed_min", "Time in bed (min)"), ("asleep_min", "Time asleep (min)"),
           ("latency_min", "Sleep onset latency (min)"), ("snore_min", "Snore time (min)"),
           ("quality", "Sleep score / quality (%)")]


def report(pairs, unknown, their_hyp=None, ref_hyp=None, n_ours=0, n_theirs=0) -> tuple[str, dict]:
    L = ["# Night benchmark — ours vs the original app\n",
         f"Nights: {n_ours} ours, {n_theirs} theirs, **{len(pairs)} paired** (>= 50% time overlap). "
         "Their export only grades ours; it is never used for training.\n"]
    if unknown:
        L.append(f"Their columns not compared: {', '.join(unknown)}\n")
    summary = {"paired": len(pairs), "metrics": {}}
    L += ["## Per night\n", "| night | " + " | ".join(f"{t} ours / theirs" for _, t in METRICS) + " |",
          "|---|" + "---|" * len(METRICS)]
    fmt = lambda v: "—" if v is None else f"{v:.0f}"  # noqa: E731
    for a, b in pairs:
        L.append(f"| {a.start:%Y-%m-%d} | " + " | ".join(f"{fmt(getattr(a, f))} / {fmt(getattr(b, f))}"
                                                        for f, _ in METRICS) + " |")
    L += ["\n## Agreement over paired nights\n",
          "| metric | n | bias (ours − theirs) | MAE | 95% limits of agreement | Pearson r |",
          "|---|---|---|---|---|---|"]
    for f, title in METRICS:
        xs = [(getattr(a, f), getattr(b, f)) for a, b in pairs]
        xs = [(x, y) for x, y in xs if x is not None and y is not None]
        s = stats([x for x, _ in xs], [y for _, y in xs])
        summary["metrics"][f] = s
        if s["n"] == 0:
            L.append(f"| {title} | 0 | — | — | — | — |")
            continue
        r = f"{s['r']:.2f}" if "r" in s else "n<3"
        L.append(f"| {title} | {s['n']} | {s['bias']:+.1f} | {s['mae']:.1f} | "
                 f"{s['loa'][0]:+.1f} … {s['loa'][1]:+.1f} | {r} |")
    sn = [(a.snore_min > 5, b.snore_min > 5) for a, b in pairs if a.snore_min is not None and b.snore_min is not None]
    if sn:
        po, k, _ = kappa(["y" if x else "n" for x, _ in sn], ["y" if y else "n" for _, y in sn], ["y", "n"])
        summary["snored_over_5min"] = {"agreement": po, "kappa": k, "n": len(sn)}
        L.append(f"\n\"Snored > 5 min\" agreement: {po:.0%} over {len(sn)} nights (kappa {k:.2f}).\n")

    def hyp_section(title, ours_h, other_h, key):
        a, b = align(ours_h, other_h)
        if not a:
            return
        labels = ["wake", "light", "deep"]
        po, k, cm = kappa(a, b, labels)
        summary[key] = {"epochs": len(a), "accuracy": po, "kappa": k}
        L.extend([f"\n## {title}\n", f"{len(a)} epochs of 30 s · accuracy {po:.0%} · Cohen's kappa {k:.2f}\n",
                  "| ours \\ other | " + " | ".join(labels) + " |", "|---|---|---|---|"])
        L.extend(f"| {labels[i]} | " + " | ".join(str(v) for v in row) + " |" for i, row in enumerate(cm))

    hyp = their_hyp or ref_hyp
    if pairs and hyp:
        # hypnogram files cover one night: score the paired night they overlap most
        def overlap(n):
            return (min(n.end, hyp[-1][0]) - max(n.start, hyp[0][0])).total_seconds()
        ours0 = max((a for a, _ in pairs), key=overlap).hypnogram
        if their_hyp:
            hyp_section("Hypnogram vs the original app", ours0, their_hyp, "hypnogram_vs_theirs")
        if ref_hyp:
            hyp_section("Hypnogram vs reference (ours)", ours0, ref_hyp, "hypnogram_ours_vs_reference")
            if their_hyp:
                hyp_section("Hypnogram vs reference (theirs)", their_hyp, ref_hyp, "hypnogram_theirs_vs_reference")
    L.append("\nReading this: the original app is not ground truth (phone trackers don't reliably "
             "separate sleep from wake against PSG — see MODELS_findings.md). Close agreement means "
             "\"as good as the original\", not \"correct\"; a reference hypnogram is what measures correctness.\n")
    return "\n".join(L), summary


# --------------------------------------------------------------------------- self-test

def selftest() -> None:
    import random
    rnd = random.Random(0)
    d = tempfile.mkdtemp(prefix="bench_")
    ours, theirs_rows, their_hyp = [], [], []
    for k in range(5):
        start = datetime(2026, 10, 10 + k, 23, rnd.randint(0, 50))
        n = 2 * 60 * 7 + rnd.randint(0, 60)
        phases = []
        for i in range(n):
            cyc = (i % 180) / 180
            st = "awake" if i < 20 else ("deep" if cyc < 0.3 and i < n / 2 else ("rem" if cyc > 0.8 else "light"))
            phases.append({"t": i, "phase": st})
        end = start + timedelta(seconds=EPOCH * n)
        snore = rnd.randint(0, 40)
        ours.append({"session": {"startedAt": int(start.timestamp() * 1000), "endedAt": int(end.timestamp() * 1000),
                                 "phases": phases, "snoreEvents": 3, "snorePercent": 5.0,
                                 "sleepScore": 70 + rnd.randint(0, 20)}, "snoreMinutes": snore})
        ts, te = start + timedelta(minutes=rnd.randint(-5, 5)), end + timedelta(minutes=rnd.randint(-5, 5))
        theirs_rows.append([ts.strftime("%Y-%m-%d %H:%M:%S"), te.strftime("%Y-%m-%d %H:%M:%S"),
                            f"{70 + rnd.randint(0, 20)}%", str(int((te - ts).total_seconds())),
                            str(int((te - ts).total_seconds() * 0.9)), str(600), str(max(0, snore + rnd.randint(-8, 8)) * 60),
                            "Night 1"])
        if k == 0:
            for i, p in enumerate(phases):
                st = p["phase"] if rnd.random() > 0.25 else rnd.choice(["awake", "light", "deep"])
                their_hyp.append(((start + timedelta(seconds=EPOCH * i)).strftime("%Y-%m-%d %H:%M:%S"),
                                  "light" if st == "rem" else st))
    json.dump(ours, open(os.path.join(d, "ours.json"), "w"))
    with open(os.path.join(d, "theirs.csv"), "w", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["Start", "End", "Sleep Quality", "Time in bed (seconds)", "Time asleep (seconds)",
                    "Time before sleep (seconds)", "Snore time (seconds)", "Notes"])
        w.writerows(theirs_rows)
    with open(os.path.join(d, "their_hyp.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "stage"])
        w.writerows(their_hyp)
    o = read_ours(os.path.join(d, "ours.json"))
    t, unknown = read_theirs(os.path.join(d, "theirs.csv"))
    text, s = report(pair(o, t), unknown, read_hypnogram(os.path.join(d, "their_hyp.csv")),
                     n_ours=len(o), n_theirs=len(t))
    assert s["paired"] == 5, s
    assert s["metrics"]["in_bed_min"]["mae"] < 11, s["metrics"]["in_bed_min"]
    assert 0.5 < s["hypnogram_vs_theirs"]["accuracy"] < 0.95, s["hypnogram_vs_theirs"]
    assert unknown == ["Notes"], unknown
    print(text)
    print("\nselftest OK —", d)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ours")
    ap.add_argument("--theirs")
    ap.add_argument("--their-hypnogram")
    ap.add_argument("--reference-hypnogram")
    ap.add_argument("--out", help="write the markdown report here (and a .json summary beside it)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not (a.ours and a.theirs):
        ap.error("--ours and --theirs are required")
    ours = read_ours(a.ours)
    theirs, unknown = read_theirs(a.theirs)
    text, summary = report(pair(ours, theirs), unknown,
                           read_hypnogram(a.their_hypnogram) if a.their_hypnogram else None,
                           read_hypnogram(a.reference_hypnogram) if a.reference_hypnogram else None,
                           n_ours=len(ours), n_theirs=len(theirs))
    if a.out:
        open(a.out, "w").write(text)
        json.dump(summary, open(os.path.splitext(a.out)[0] + ".json", "w"), indent=2, default=str)
        print(f"wrote {a.out}")
    else:
        print(text)


if __name__ == "__main__":
    sys.exit(main())
