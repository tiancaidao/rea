"""
Train the on-device sleep-staging model (Part C) and compare it with the app's
current heuristic stager.

Input: the app's per-30-s movement number (staging_data.py) for a whole night,
turned into 4 per-epoch features that the phone can compute after the night:

    f1 = log1p(10 * raw / p95(night raw))      movement relative to the night's busy epochs
    f2 = log1p(raw / median(night raw))        movement relative to the night's baseline
    f3 = hours since the night started / 8
    f4 = hours until the night ended / 8

Model: a small non-causal dilated temporal CNN (receptive field ~+-31 min) over
the epoch sequence, with a 4-class head (wake / light / deep / REM) and a
wake-vs-sleep head. About 17k parameters, run in pure Dart on the phone after
tracking. Splits are by subject; selection on val only; test is scored once.

  python3 training/staging_data.py
  python3 training/train_stage.py

Outputs (gitignored): stage_model.onnx, flutter_app/assets/models/stage_tcn.json.
Metrics -> STAGING_RESULTS.md (committed).
"""
from __future__ import annotations
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from staging_data import OUT as FEATURES, STAGES, VARIANTS, EPOCH  # noqa: E402

FLUTTER_MODEL = os.path.join(HERE, "..", "..", "flutter_app", "assets", "models", "stage_tcn.json")
WIDTH, KERNEL, DILATIONS = 32, 5, (2, 4, 8, 16)
PHONE_VARIANT = 6  # (attenuation 0.1, 5-sample smoothing, noise): the phone-like test condition


def features(raw: np.ndarray) -> np.ndarray:
    """(n,) per-epoch movement -> (4, n). Mirrored in flutter_app/lib/sensing/stage_model.dart."""
    n = len(raw)
    s = np.sort(raw)
    p95, med = s[int(0.95 * (n - 1))], s[int(0.5 * (n - 1))]
    t = np.arange(n) * EPOCH / 3600.0
    return np.stack([np.log1p(10 * raw / (p95 + 1e-6)), np.log1p(raw / (med + 1e-6)),
                     t / 8.0, (t[-1] - t) / 8.0]).astype(np.float32)


# --------------------------------------------------------------------------- heuristic baseline
# exact port of estimateStages() in flutter_app/lib/core/sleep_algorithms.dart

def heuristic(raw: np.ndarray) -> np.ndarray:
    mx = raw.max()
    m = np.clip(raw / mx if mx > 0 else raw * 0, 0, 1)
    radius, sigma = 3, 1.5
    k = np.exp(-np.arange(-radius, radius + 1) ** 2 / (2 * sigma ** 2))
    k /= k.sum()
    n = len(m)
    mv = np.array([sum(m[min(max(i + j - radius, 0), n - 1)] * k[j] for j in range(len(k))) for i in range(n)])
    cyc = (90 * 60) // EPOCH
    bell = lambda x, mu, sg: math.exp(-((x - mu) ** 2) / (2 * sg * sg))  # noqa: E731
    out = np.full(n, 1)
    for i in range(n):
        if mv[i] > 0.55:
            out[i] = 0
            continue
        ci, pos = i / cyc, (i % cyc) / cyc
        deep = max(0.0, 1.0 - ci * 0.45) * bell(pos, 0.3, 0.18) - mv[i]
        rem = min(max(0.15 + ci * 0.28, 0.0), 1.0) * bell(pos, 0.85, 0.12)
        light = 0.35 + 0.5 * mv[i]
        if deep >= rem and deep >= light and mv[i] < 0.25:
            out[i] = 2
        elif rem > light and rem >= deep:
            out[i] = 3
    out[: min(6, n)] = np.where(np.isin(out[: min(6, n)], (2, 3)), 1, out[: min(6, n)])
    out[max(0, n - 4):] = 0
    return out


# --------------------------------------------------------------------------- metrics

def kappa(a, b, k):
    cm = np.zeros((k, k), np.int64)
    np.add.at(cm, (a, b), 1)
    n = cm.sum()
    po = np.trace(cm) / n
    pe = (cm.sum(0) * cm.sum(1)).sum() / n ** 2
    return po, (po - pe) / (1 - pe) if pe < 1 else float("nan"), cm


def evaluate(pred_by_night, true_by_night, valid_by_night):
    p = np.concatenate([q[v & (t >= 0)] for q, t, v in zip(pred_by_night, true_by_night, valid_by_night)])
    t = np.concatenate([t[v & (t >= 0)] for t, v in zip(true_by_night, valid_by_night)])
    acc, k4, cm = kappa(t, p, 4)
    _, k2, _ = kappa((t == 0).astype(int), (p == 0).astype(int), 2)
    recall = cm.diagonal() / np.maximum(cm.sum(1), 1)
    per_night = [kappa(tt[v & (tt >= 0)], pp[v & (tt >= 0)], 4)[1]
                 for pp, tt, v in zip(pred_by_night, true_by_night, valid_by_night)]
    return dict(acc=acc, kappa4=k4, kappa_sw=k2, recall=recall, cm=cm, kappa4_night=float(np.nanmean(per_night)))


# --------------------------------------------------------------------------- model

def viterbi(logits, log_trans):
    """Most likely stage path given per-epoch logits and stage transition log-probs.
    Mirrored in flutter_app/lib/sensing/stage_model.dart."""
    em = logits - logits.max(1, keepdims=True)
    em = em - np.log(np.exp(em).sum(1, keepdims=True))
    dp, back = em[0].copy(), np.zeros((len(em), 4), int)
    for t in range(1, len(em)):
        c = dp[:, None] + log_trans
        back[t], dp = c.argmax(0), c.max(0) + em[t]
    path = [int(dp.argmax())]
    for t in range(len(em) - 1, 0, -1):
        path.append(int(back[t][path[-1]]))
    return np.array(path[::-1])


def build_model(width=WIDTH, dilations=DILATIONS):
    import torch.nn as nn
    import torch

    class StageTCN(nn.Module):
        def __init__(self):
            super().__init__()
            self.dilations = list(dilations)
            self.inp = nn.Conv1d(4, width, KERNEL, padding=KERNEL // 2)
            self.blocks = nn.ModuleList([nn.Conv1d(width, width, KERNEL, dilation=d, padding=d * (KERNEL // 2))
                                         for d in dilations])
            self.drop = nn.Dropout(0.1)
            self.stage = nn.Conv1d(width, 4, 1)
            self.wake = nn.Conv1d(width, 1, 1)

        def forward(self, x):  # (B, 4, T) -> (B, 4, T), (B, 1, T)
            h = torch.relu(self.inp(x))
            for b in self.blocks:
                h = h + self.drop(torch.relu(b(h)))
            return self.stage(h), self.wake(h)

    return StageTCN()


def main():
    import torch
    import torch.nn.functional as F

    d = np.load(FEATURES, allow_pickle=True)
    split, raws, stages, valids, srcs = d["split"], d["raw"], d["stage"], d["valid"], d["source"]
    idx = {s: np.where(split == s)[0] for s in ("train", "val", "test")}
    counts = np.bincount(np.concatenate([stages[i][stages[i] >= 0] for i in idx["train"]]), minlength=4)
    cw = torch.tensor((counts.sum() / (4 * counts)) ** 0.5, dtype=torch.float32)
    print("train epochs per stage", dict(zip(STAGES, counts.tolist())), "weights", cw.numpy().round(2))

    # stage transitions from the train PSG labels, for Viterbi smoothing of the
    # model's per-epoch probabilities (chosen on val in IMPROVEMENTS.md)
    A = np.ones((4, 4))
    for i in idx["train"]:
        s_ = stages[i]
        for a, b in zip(s_[:-1], s_[1:]):
            if a >= 0 and b >= 0:
                A[a, b] += 1
    log_trans = np.log(A / A.sum(1, keepdims=True))
    use_viterbi = [True]

    def predict(model, i, variant):
        model.eval()
        with torch.no_grad():
            lo, _ = model(torch.tensor(features(raws[i][variant]))[None])
        lo = lo[0].T.numpy()
        return viterbi(lo, log_trans) if use_viterbi[0] else lo.argmax(1)

    def score(model, ids, variant):
        return evaluate([predict(model, i, variant) for i in ids], [stages[i] for i in ids], [valids[i] for i in ids])

    torch.manual_seed(0)
    rng = np.random.default_rng(0)
    model = build_model()
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=1e-3)
    epochs = 80
    best, best_state, best_ep = -1, None, 0
    for ep in range(epochs):
        model.train()
        order = rng.permutation(idx["train"])
        for b in range(0, len(order), 4):
            batch = order[b:b + 4]
            T = max(len(stages[i]) for i in batch)
            x = torch.zeros(len(batch), 4, T)
            y = torch.full((len(batch), T), -1, dtype=torch.long)
            for j, i in enumerate(batch):
                v = 0 if rng.random() < 0.3 else rng.integers(1, len(VARIANTS))
                n = len(stages[i])
                x[j, :, :n] = torch.tensor(features(raws[i][v]))
                yy = stages[i].copy()
                yy[~valids[i]] = -1
                y[j, :n] = torch.tensor(yy)
            lo, lw = model(x)
            m = y >= 0
            loss = F.cross_entropy(lo.permute(0, 2, 1)[m], y[m], weight=cw) + \
                0.5 * F.binary_cross_entropy_with_logits(lw[:, 0][m], (y[m] == 0).float())
            opt.zero_grad()
            loss.backward()
            opt.step()
        if (ep + 1) % 2 == 0:
            # select on val, averaged over the wrist recording and the phone-like rendering
            use_viterbi[0] = False  # epoch selection on the raw model, as in the ablation
            sv = np.mean([score(model, idx["val"], v)["kappa4"] for v in (0, PHONE_VARIANT)])
            use_viterbi[0] = True
            if sv > best:
                best, best_ep = sv, ep + 1
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
            print(f"epoch {ep + 1:3d} loss={loss.item():.3f} val kappa4 (wrist/phone avg)={sv:.3f}", flush=True)
    model.load_state_dict(best_state)

    results = {}
    for name, v in (("wrist", 0), ("phone-like", PHONE_VARIANT)):
        use_viterbi[0] = False
        results[("model, argmax", name)] = score(model, idx["test"], v)
        use_viterbi[0] = True
        results[("model", name)] = score(model, idx["test"], v)
        results[("heuristic", name)] = evaluate([heuristic(raws[i][v]) for i in idx["test"]],
                                                [stages[i] for i in idx["test"]], [valids[i] for i in idx["test"]])
    by_source = {}
    for src in sorted(set(srcs)):
        ids = [i for i in idx["test"] if srcs[i] == src]
        by_source[src] = (len(ids), score(model, ids, 0), score(model, ids, PHONE_VARIANT),
                          evaluate([heuristic(raws[i][0]) for i in ids], [stages[i] for i in ids],
                                   [valids[i] for i in ids]))
    for (who, cond), r in results.items():
        print(f"test {who:9s} {cond:10s} acc={r['acc']:.3f} kappa4={r['kappa4']:.3f} kappa_sw={r['kappa_sw']:.3f} "
              f"recall={np.round(r['recall'], 2).tolist()}")
    export(model, raws[idx["test"][0]][PHONE_VARIANT], dict(log_trans=log_trans.round(6).tolist()))
    write_results(results, best_ep, {s: len(v) for s, v in idx.items()}, counts, by_source)


def export(model, sample_raw, hmm=None):
    import torch
    model.eval()
    onnx_path = os.path.join(HERE, "stage_model.onnx")
    torch.onnx.export(model, torch.zeros(1, 4, 960), onnx_path, dynamo=False, input_names=["features"],
                      output_names=["stage_logits", "wake_logit"],
                      dynamic_axes={"features": {2: "epochs"}, "stage_logits": {2: "epochs"}, "wake_logit": {2: "epochs"}})
    convs = [model.inp] + list(model.blocks)
    with torch.no_grad():
        lo, lw = model(torch.tensor(features(sample_raw))[None])
    blob = dict(
        version=1, stages=STAGES, kernel=KERNEL, dilations=[1] + list(model.dilations),
        width=model.inp.out_channels, hmm=hmm,
        convs=[dict(out=c.out_channels, inp=c.in_channels, w=c.weight.detach().flatten().tolist(),
                    b=c.bias.detach().tolist()) for c in convs],
        stage_head=dict(w=model.stage.weight.detach().flatten().tolist(), b=model.stage.bias.detach().tolist()),
        wake_head=dict(w=model.wake.weight.detach().flatten().tolist(), b=model.wake.bias.detach().tolist()),
        parity=dict(raw=sample_raw.round(4).tolist(), stage_logits=lo[0].T.numpy().round(5).tolist(),
                    wake_logit=lw[0, 0].numpy().round(5).tolist(),
                    stages=(viterbi(lo[0].T.numpy(), np.array(hmm["log_trans"])) if hmm
                            else lo[0].argmax(0).numpy()).tolist()),
    )
    os.makedirs(os.path.dirname(FLUTTER_MODEL), exist_ok=True)
    json.dump(blob, open(FLUTTER_MODEL, "w"), separators=(",", ":"))
    print(f"exported {onnx_path} and {os.path.normpath(FLUTTER_MODEL)} ({os.path.getsize(FLUTTER_MODEL) // 1024} KB)")


MANUAL_MARKER = "<!-- below this line is maintained by hand; train_stage.py keeps it -->"


def write_results(results, best_ep, n_nights, counts, by_source=None):
    L = ["# Sleep-staging model results (Part C)\n",
         "**Input:** motion only. That's the app's per-30-s movement number (summed |Δ|acceleration| + "
         "spikes > 0.03 g at 50 Hz), normalised per night, plus time since start and until the end of "
         "the night. **Model:** our own dilated temporal CNN (~17k params, receptive field ±31 min), "
         "4 stages + a wake head, trained from scratch on open data (see `DATASETS.md`). No Sleep Cycle "
         "weights or outputs are used.\n",
         f"**Data:** Walch et al. 2019 (PhysioNet sleep-accel, ODC-By 1.0; healthy adults, Apple Watch) and "
         f"Newcastle 2015 (van Hees, CC BY 4.0; sleep-clinic patients, GENEActiv), wrist accelerometer + PSG, "
         f"nights split by subject within each source: {n_nights['train']} train / {n_nights['val']} val / "
         f"{n_nights['test']} test. "
         f"Train epochs: " + ", ".join(f"{s} {c}" for s, c in zip(STAGES, counts)) + ". "
         f"Model chosen on val (epoch {best_ep}); test scored once.\n",
         "Per-epoch probabilities are smoothed with Viterbi decoding over stage transitions "
         "estimated from the train PSG labels (picked on val, see IMPROVEMENTS.md).\n",
         "**Conditions:** *wrist* = the sensor as recorded. *phone-like* = the same nights with motion "
         "attenuated 10×, smoothed and given phone sensor noise. That's a stand-in for a phone on the "
         "mattress, which we can't get with PSG labels from open data.\n",
         "| stager | condition | accuracy | κ 4-stage | κ sleep/wake | κ 4-stage (mean per night) | "
         "recall wake / light / deep / REM |", "|---|---|---|---|---|---|---|"]
    for (who, cond), r in results.items():
        L.append(f"| {dict(model='our model (+ Viterbi, shipped)').get(who, 'our model, no smoothing' if 'argmax' in who else 'current heuristic')} | {cond} | {r['acc']:.3f} | "
                 f"{r['kappa4']:.3f} | {r['kappa_sw']:.3f} | {r['kappa4_night']:.3f} | "
                 + " / ".join(f"{x:.2f}" for x in r["recall"]) + " |")
    if by_source:
        L += ["\n**By test source** (κ 4-stage / κ sleep-wake):\n",
              "| source | test nights | our model, wrist | our model, phone-like | heuristic, wrist |",
              "|---|---|---|---|---|"]
        for src, (n, a, b, h) in by_source.items():
            L.append(f"| {src} | {n} | {a['kappa4']:.2f} / {a['kappa_sw']:.2f} | {b['kappa4']:.2f} / "
                     f"{b['kappa_sw']:.2f} | {h['kappa4']:.2f} / {h['kappa_sw']:.2f} |")
    for cond in ("wrist", "phone-like"):
        cm = results[("model", cond)]["cm"]
        L += [f"\n**Confusion matrix, our model, {cond}** (rows = PSG, cols = predicted; wake, light, deep, REM):\n",
              "```"] + [" ".join(f"{v:6d}" for v in row) for row in cm] + ["```"]
    L += ["\n**Published reference points** (MODELS_findings.md): phone apps incl. Sleep Cycle do not reliably "
          "separate sleep from wake vs PSG. Wrist wearables *with heart rate* reach κ ≈ 0.5 for 4 stages "
          "(Apple Watch S8 κ 0.53; Apple's own κ ≈ 0.63; Google accel+PPG κ 0.66). Experts agree at κ ≈ 0.70–0.75. "
          "Motion-only staging cannot see REM vs deep directly, so a 4-stage κ well below the heart-rate "
          "wearables is expected. Sleep/wake is where motion carries the signal.\n"]
    p = os.path.join(HERE, "STAGING_RESULTS.md")
    manual = ""
    if os.path.isfile(p) and MANUAL_MARKER in open(p).read():
        manual = open(p).read().split(MANUAL_MARKER, 1)[1]
    open(p, "w").write("\n".join(L) + "\n" + MANUAL_MARKER + manual)
    print(f"wrote {p}")


if __name__ == "__main__":
    main()
