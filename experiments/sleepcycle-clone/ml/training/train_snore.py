"""
Train the snore / sound-event classifier and export it for the app.

Input is the app's recovered front-end contract — a [1, 1, 86, 64] log-mel
patch (44.1 kHz -> 2048-pt FFT -> 64 mel -> 86 frames, ~2 s) — into our own
compact 2D-CNN (snore_classifier.build_model) -> snore / cough / speech / other.
Our weights, trained only on the openly-licensed sets in DATASETS.md.

Precision matters more than accuracy for snore minutes (a fan or a partner
talking must not count as snoring), so besides argmax metrics we pick a snore
decision threshold on the validation split for F0.5 (precision-weighted) and
report test precision / recall / false alarms per hour at that threshold.

  python3 training/prepare_data.py --download && python3 training/prepare_data.py
  python3 training/train_snore.py

Outputs (gitignored): snore_classifier.onnx, snore_norm.npz,
flutter_app/assets/models/snore_cnn.json (BN-folded weights for the Dart
runtime + parity vectors). Metrics -> RESULTS.md (committed).
"""
from __future__ import annotations
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ML = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, ML)

import numpy as np  # noqa: E402
from audio_pipeline import LOG_FLOOR, FMAX_HZ, SAMPLE_RATE, FFT_SIZE, HOP, N_MELS, N_FRAMES  # noqa: E402
from snore_classifier import build_model  # noqa: E402

FEATURES = os.path.join(ML, "data", "features.npz")
FLUTTER_MODEL = os.path.join(ML, "..", "flutter_app", "assets", "models", "snore_cnn.json")
SNORE = 0
MANUAL_MARKER = "<!-- below this line is maintained by hand; train_snore.py keeps it -->"


def metrics(y_true, y_pred, labels):
    n = len(labels)
    cm = np.zeros((n, n), np.int64)
    for t, p in zip(y_true, y_pred):
        cm[t, p] += 1
    per = {}
    for c in range(n):
        tp, fp, fn = cm[c, c], cm[:, c].sum() - cm[c, c], cm[c, :].sum() - cm[c, c]
        pr = tp / (tp + fp) if tp + fp else 0.0
        rc = tp / (tp + fn) if tp + fn else 0.0
        per[labels[c]] = dict(precision=pr, recall=rc, f1=2 * pr * rc / (pr + rc) if pr + rc else 0.0,
                              support=int(cm[c].sum()))
    return np.trace(cm) / cm.sum(), per, cm


def average_precision(scores, positive):
    order = np.argsort(-scores)
    pos = positive[order]
    if pos.sum() == 0:
        return 0.0
    hits = np.cumsum(pos)
    return float((hits / np.arange(1, len(pos) + 1))[pos].mean())


def binary_at(scores, positive, t):
    pred = scores >= t
    tp, fp = int((pred & positive).sum()), int((pred & ~positive).sum())
    fn = int((~pred & positive).sum())
    pr = tp / (tp + fp) if tp + fp else 1.0
    rc = tp / (tp + fn) if tp + fn else 0.0
    # each patch is ~1 s of audio (patches are cut ~1 s apart)
    fa_per_hour = fp / max(1, (~positive).sum()) * 3600
    return pr, rc, fa_per_hour, tp, fp, fn


def pick_threshold(scores, positive, beta=0.5):
    best = (0.5, -1.0)
    for t in np.linspace(0.05, 0.99, 95):
        pr, rc, *_ = binary_at(scores, positive, t)
        f = (1 + beta ** 2) * pr * rc / (beta ** 2 * pr + rc) if pr + rc else 0.0
        if f > best[1]:
            best = (float(t), f)
    return best[0]


def main():
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    d = np.load(FEATURES)
    labels = [str(x) for x in d["labels"]]
    X, y, split = d["X"].astype(np.float32), d["y"], d["split"]
    neg = d["neg_group"]
    tr, va, te = split == "train", split == "val", split == "test"
    mean, std = float(X[tr].mean()), float(X[tr].std() + 1e-6)

    def augment(xb_raw, bg):
        """xb_raw: un-normalized log-mel. Gain, background mix, SpecAugment, roll."""
        b = xb_raw.shape[0]
        lin = torch.exp(xb_raw) - LOG_FLOOR
        lin = lin * torch.exp(torch.empty(b, 1, 1, 1).uniform_(-1.5, 1.5))      # about +-13 dB
        mix = torch.rand(b) < 0.5
        if mix.any():
            idx = torch.randint(0, len(bg), (int(mix.sum()),))
            k = torch.exp(torch.empty(int(mix.sum()), 1, 1, 1).uniform_(-3.0, 0.0))
            lin[mix] = lin[mix] + (torch.exp(bg[idx]) - LOG_FLOOR) * k
        x = (torch.log(lin.clamp_min(0) + LOG_FLOOR) - mean) / std
        for i in range(b):
            if torch.rand(1) < 0.5:
                f0 = int(torch.randint(0, N_MELS - 8, (1,)))
                x[i, :, :, f0:f0 + int(torch.randint(1, 8, (1,)))] = 0
            if torch.rand(1) < 0.5:
                t0 = int(torch.randint(0, N_FRAMES - 12, (1,)))
                x[i, :, t0:t0 + int(torch.randint(1, 12, (1,))), :] = 0
        return torch.roll(x, int(torch.randint(-20, 21, (1,))), dims=2)

    def probs(model, xraw):
        model.eval()
        xt = torch.tensor((xraw - mean) / std)
        with torch.no_grad():
            return torch.cat([F.softmax(model(xt[i:i + 512]), 1) for i in range(0, len(xt), 512)]).numpy()

    def fit(mask, epochs, steps=120, val_mask=None, boost=None):
        """Train on X[mask]. Within "other", every negative group is drawn equally
        often (times boost[group] for groups that leaked into snore). With val_mask,
        track the best epoch by 0.5 * snore AP + 0.5 * macro-F1 and return
        (model at best epoch, best epoch)."""
        torch.manual_seed(0)
        Xr, yt = torch.tensor(X[mask]), torch.tensor(y[mask])
        bg = Xr[yt == labels.index("other")]
        counts = np.bincount(y[mask], minlength=len(labels)).astype(np.float64)
        w_class = 1.0 / np.sqrt(counts)          # each class drawn ~ sqrt of its share
        w_class[SNORE] *= 3.0                    # and the scarce snore class oversampled
        w = w_class[y[mask]]
        g = neg[mask]
        groups = sorted(set(g[g != ""]))
        for gr in groups:
            m = g == gr
            w[m] *= (g != "").sum() / (len(groups) * m.sum()) * (boost or {}).get(gr, 1.0)
        sampler_w = torch.tensor(w, dtype=torch.double)
        model = build_model(len(labels))
        opt = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=1e-3)
        sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=3e-3, total_steps=epochs * steps)
        lossf = nn.CrossEntropyLoss(label_smoothing=0.05)
        best, best_ep, best_state = -1.0, epochs, None
        for ep in range(epochs):
            model.train()
            idx_all = torch.multinomial(sampler_w, steps * 64, replacement=True)
            for s in range(steps):
                idx = idx_all[s * 64:(s + 1) * 64]
                opt.zero_grad()
                loss = lossf(model(augment(Xr[idx], bg)), yt[idx])
                loss.backward()
                opt.step()
                sched.step()
            if val_mask is None:
                continue
            pv = probs(model, X[val_mask])
            ap = average_precision(pv[:, SNORE], y[val_mask] == SNORE)
            _, per, _ = metrics(y[val_mask], pv.argmax(1), labels)
            macro = np.mean([m["f1"] for m in per.values() if m["support"]])
            score = 0.5 * ap + 0.5 * macro
            if score > best:
                best, best_ep, best_state = score, ep + 1, {k: v.clone() for k, v in model.state_dict().items()}
            print(f"epoch {ep + 1:2d} loss={loss.item():.3f} val snoreAP={ap:.3f} macroF1={macro:.3f}", flush=True)
        if best_state is not None:
            model.load_state_dict(best_state)
        return model, best_ep

    # 1) train on train, pick the epoch count and the snore threshold on val
    model, best_ep = fit(tr, epochs=40, val_mask=va)
    pv = probs(model, X[va])
    thr = pick_threshold(pv[:, SNORE], y[va] == SNORE)
    print(f"best epoch {best_ep}, val-chosen snore threshold {thr:.2f}")
    # a negative group that leaks toward snore on val — >2% of its patches at
    # P(snore) >= thr/2, i.e. false alarms plus near-misses — is drawn 3x as often
    # in the final fit (hard-negative rebalancing)
    val_leak = group_fp(pv[:, SNORE], neg[va], thr)
    near = group_fp(pv[:, SNORE], neg[va], thr / 2)
    boost = {str(g): 3.0 for g, (fp, n) in near.items() if fp >= 2 and fp / n > 0.02}
    print("val leaks into snore:", {g: f"{fp}/{n}" for g, (fp, n) in val_leak.items() if fp}, "boost:", boost)
    # 2) retrain from scratch on train+val for that many epochs (snore data is too
    #    scarce to leave a fifth of it out of the shipped model); test stays untouched
    model, _ = fit(tr | va, epochs=max(best_ep, 10), boost=boost)
    pt = probs(model, X[te])
    acc, per, cm = metrics(y[te], pt.argmax(1), labels)
    snore_ap = average_precision(pt[:, SNORE], y[te] == SNORE)
    bin_thr = binary_at(pt[:, SNORE], y[te] == SNORE, thr)
    bin_argmax = binary_at(pt[:, SNORE], y[te] == SNORE, 0.5)
    clip = clip_level(pt[:, SNORE], y[te], d["group"][te], d["source"][te], thr)
    print(f"\ntest acc={acc:.3f} snoreAP={snore_ap:.3f} thr={thr:.2f} -> P={bin_thr[0]:.2f} R={bin_thr[1]:.2f} "
          f"FA/h={bin_thr[2]:.1f} | clip-level P={clip[0]:.2f} R={clip[1]:.2f}")
    for c, m in per.items():
        print(f"  {c:7s} P={m['precision']:.2f} R={m['recall']:.2f} F1={m['f1']:.2f} n={m['support']}")

    export(model, labels, mean, std, thr, torch.tensor((X[te][:4] - mean) / std))
    test_leak = group_fp(pt[:, SNORE], neg[te], thr)
    print("test leaks into snore:", {g: f"{fp}/{n}" for g, (fp, n) in test_leak.items() if fp})
    write_results(acc, per, cm, labels, snore_ap, thr, bin_thr, bin_argmax, clip, best_ep, d, y, split, pt,
                  val_leak, test_leak, boost)


def group_fp(p_snore, neg_group, thr):
    """Per negative group: (patches called snore, patches)."""
    return {g: (int((p_snore[neg_group == g] >= thr).sum()), int((neg_group == g).sum()))
            for g in sorted(set(neg_group[neg_group != ""]))}


def clip_level(p_snore, y, group, source, thr, min_hits=2):
    """ESC-50 test clips (5 s): call a clip snoring when >= min_hits of its
    patches pass the threshold — the same idea as the app's event smoothing
    (majority vote + minimum event length) applied to a 5 s clip."""
    clips = {}
    for p, t, g, s in zip(p_snore, y, group, source):
        if s != "esc50":
            continue
        hits, pos = clips.get(g, (0, False))
        clips[g] = (hits + (p >= thr), pos or t == SNORE)
    tp = sum(1 for h, pos in clips.values() if h >= min_hits and pos)
    fp = sum(1 for h, pos in clips.values() if h >= min_hits and not pos)
    fn = sum(1 for h, pos in clips.values() if h < min_hits and pos)
    fp_clips = sorted(g for g, (h, pos) in clips.items() if h >= min_hits and not pos)
    return (tp / (tp + fp) if tp + fp else 1.0, tp / (tp + fn) if tp + fn else 0.0, tp, fp, fn, fp_clips,
            sum(1 for _, pos in clips.values() if not pos))


def export(model, labels, mean, std, thr, sample):
    import torch
    model.eval()
    onnx_path = os.path.join(HERE, "snore_classifier.onnx")
    torch.onnx.export(model, torch.zeros(1, 1, N_FRAMES, N_MELS), onnx_path, dynamo=False,
                      input_names=["mel"], output_names=["logits"],
                      dynamic_axes={"mel": {0: "batch"}, "logits": {0: "batch"}})
    np.savez(os.path.join(HERE, "snore_norm.npz"), mean=mean, std=std, labels=np.array(labels), threshold=thr)

    # ONNX Runtime parity with PyTorch
    import onnxruntime as ort
    sess = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    ref = model(sample).detach().numpy()
    got = sess.run(None, {"mel": sample.numpy()})[0]
    print(f"exported {onnx_path}  (onnxruntime max|diff| vs torch = {np.abs(ref - got).max():.2e})")

    # Flat, BN-folded weights for the pure-Dart runtime (no native ML dependency)
    convs = []
    for blk in model.features:
        conv, bn = blk[0], blk[1]
        s = (bn.weight / torch.sqrt(bn.running_var + bn.eps)).detach()
        w = conv.weight.detach() * s[:, None, None, None]
        b = (conv.bias.detach() - bn.running_mean) * s + bn.bias.detach()
        convs.append(dict(out=w.shape[0], inp=w.shape[1], w=w.flatten().tolist(), b=b.tolist()))
    lin = model.head[2]
    # parity vectors: raw (un-normalized) patches and the expected softmax
    raw = sample.numpy() * std + mean
    expected = torch.softmax(model(sample), 1).detach().numpy()
    blob = dict(
        version=1, labels=labels, mean=mean, std=std, snore_threshold=thr,
        frontend=dict(sample_rate=SAMPLE_RATE, fft=FFT_SIZE, hop=HOP, mels=N_MELS, frames=N_FRAMES,
                      fmax_hz=FMAX_HZ, log_floor=LOG_FLOOR),
        convs=convs, linear=dict(w=lin.weight.detach().flatten().tolist(), b=lin.bias.detach().tolist()),
        parity=[dict(x=r.flatten().round(5).tolist(), p=e.tolist()) for r, e in zip(raw[:2], expected[:2])],
    )
    os.makedirs(os.path.dirname(FLUTTER_MODEL), exist_ok=True)
    with open(FLUTTER_MODEL, "w") as f:
        json.dump(blob, f, separators=(",", ":"))
    print(f"exported {os.path.normpath(FLUTTER_MODEL)} ({os.path.getsize(FLUTTER_MODEL) // 1024} KB)")


def _esc_categories():
    import csv
    meta = os.path.join(ML, "data", "ESC-50", "meta", "esc50.csv")
    return {r["filename"]: r["category"] for r in csv.DictReader(open(meta))} if os.path.isfile(meta) else {}


def write_results(acc, per, cm, labels, snore_ap, thr, bin_thr, bin_argmax, clip, best_ep, d, y, split, pt,
                  val_leak, test_leak, boost):
    src, grp, cat = d["source"], d["group"], _esc_categories()
    counts = {sp: {labels[c]: int(((y == c) & (split == sp)).sum()) for c in range(len(labels))}
              for sp in ("train", "val", "test")}
    te = split == "test"
    # where the snore false alarms come from (test split, at the chosen threshold)
    fa = pt[:, SNORE] >= thr
    fa_src = {}
    te_idx = np.where(te)[0]
    for j, i in enumerate(te_idx):
        if fa[j] and y[i] != SNORE:
            k = f"{d['neg_group'][i] or labels[y[i]]} / {cat.get(str(grp[i]), src[i])}"
            fa_src[k] = fa_src.get(k, 0) + 1
    L = [
        "# Model results\n",
        "## Snore / sound-event classifier (Part A)\n",
        "**Contract:** [1,1,86,64] log-mel patch — 44.1 kHz → 2048-pt FFT (hop 1024) → 64 mel → "
        "86 frames (~2.02 s), the front-end recovered from the app. Mel energy above 8 kHz is "
        "dropped so 16 kHz public data and a 44.1 kHz phone mic match. "
        "**Model:** our own 3-block 2D-CNN (≈24k params) → snore / cough / speech / other. "
        "Our weights, open data only (see `DATASETS.md`); no Sleep Cycle weights or outputs used.\n",
        "**Splits** (patches; no clip / speaker / subject crosses splits — ESC-50 folds 1-3/4/5, "
        "LibriSpeech speakers hashed, EPFL subjects train vs test). Training: fit on train, pick "
        f"the epoch count ({best_ep}) and snore threshold on val, then refit from scratch on "
        "train+val and evaluate once on test:\n",
        "| split | snore | cough | speech | other |", "|---|---|---|---|---|",
    ]
    for sp, c in counts.items():
        L.append(f"| {sp} | " + " | ".join(str(c[l]) for l in labels) + " |")
    L += [
        f"\n**Held-out test, argmax:** accuracy {acc:.3f}\n",
        "| class | precision | recall | F1 | support |", "|---|---|---|---|---|",
    ]
    for c, m in per.items():
        L.append(f"| {c} | {m['precision']:.2f} | {m['recall']:.2f} | {m['f1']:.2f} | {m['support']} |")
    L += [f"\n**Confusion matrix** (rows = true, cols = predicted; {', '.join(labels)}):\n", "```"]
    L += [" ".join(f"{v:5d}" for v in row) for row in cm]
    L += ["```\n",
          "### Snore detection at the shipped threshold\n",
          f"Threshold on P(snore) chosen on the **validation** split for F0.5 (precision-weighted): "
          f"**{thr:.2f}**. Test snore average precision: **{snore_ap:.3f}**.\n",
          "| decision rule | precision | recall | false alarms / hour of non-snore audio | TP | FP | FN |",
          "|---|---|---|---|---|---|---|",
          f"| P(snore) ≥ {thr:.2f} (shipped) | {bin_thr[0]:.2f} | {bin_thr[1]:.2f} | {bin_thr[2]:.1f} | "
          f"{bin_thr[3]} | {bin_thr[4]} | {bin_thr[5]} |",
          f"| P(snore) ≥ 0.50 | {bin_argmax[0]:.2f} | {bin_argmax[1]:.2f} | {bin_argmax[2]:.1f} | "
          f"{bin_argmax[3]} | {bin_argmax[4]} | {bin_argmax[5]} |",
          f"| clip-level, ≥2 patches ≥ {thr:.2f} (5 s ESC-50 clips) | {clip[0]:.2f} | {clip[1]:.2f} | "
          f"{clip[3] / max(1, clip[6]) * 720:.1f} | {clip[2]} | {clip[3]} | {clip[4]} |",
          "\nFalse alarms per hour treat each test patch as ~1 s of audio, one decision per second, "
          "before the app's event smoothing (`detectSnoreEvents`: 3-window majority vote + minimum "
          "event length), which removes isolated single-patch false alarms.\n",
          "Patch-level test false alarms by true class / source: " + (", ".join(f"{k}: {v}" for k, v in sorted(fa_src.items()))
                                            or "none") + "\n",
          "### False positives into \"snore\" by negative group\n",
          f"Share of each \"other\" group's patches scored P(snore) ≥ {thr:.2f}. Groups leaning toward "
          f"snore on val (>2% of patches at P(snore) ≥ {thr / 2:.2f}, i.e. false alarms plus near-misses) "
          "were drawn 3× as often in the final fit: "
          + (", ".join(sorted(boost)) if boost else "none needed") + ".\n",
          "| negative group | val FP | val FP rate | test FP | test FP rate |", "|---|---|---|---|---|",
          *[f"| {g} | {val_leak.get(g, (0, 0))[0]}/{val_leak.get(g, (0, 0))[1]} | "
            f"{val_leak.get(g, (0, 1))[0] / max(1, val_leak.get(g, (0, 1))[1]):.1%} | "
            f"{test_leak[g][0]}/{test_leak[g][1]} | {test_leak[g][0] / max(1, test_leak[g][1]):.1%} |"
            for g in sorted(test_leak)],
          "",
          "### Caveats\n",
          "- The rebalancing rule was revised once after a test run: the first rule (val false "
          "alarms only) boosted only `clock`, and test then showed animals 3.5%, breathing 3.0% and "
          "clock 4.9% leaking into snore. The rule now also counts val near-misses. That is one "
          "look at test, so treat the test numbers as slightly optimistic.\n",
          f"- Only {counts['test']['snore']} snore test patches (8 ESC-50 clips): the snore numbers "
          "have wide confidence intervals. Open, permissively-licensed snore audio is scarce; "
          "the Kaggle snore set and AudioSet snoring clips were rejected on licence grounds "
          "(see DATASETS.md).\n",
          "- ESC-50 is CC BY-NC: fine for this research build, not for a commercial model. "
          "The path to a shippable model is opt-in, user-confirmed clips (`consent_sounds`).\n",
          "- Published smartphone snore CNNs reach ~95% accuracy with PPV as the weak point "
          "(MODELS_findings.md); this is the same model family on a much smaller public set.\n"]
    p = os.path.join(HERE, "RESULTS.md")
    # keep hand-written sections (on-device verification, ...) below the marker
    manual = ""
    if os.path.isfile(p) and MANUAL_MARKER in open(p).read():
        manual = open(p).read().split(MANUAL_MARKER, 1)[1]
    open(p, "w").write("\n".join(L) + "\n" + MANUAL_MARKER + manual)
    print(f"wrote {p}")


if __name__ == "__main__":
    main()
