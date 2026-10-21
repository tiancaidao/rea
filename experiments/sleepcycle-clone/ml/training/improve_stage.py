"""
Improvements pass for the staging model: try each idea, keep what helps.

Every variant is trained on the train subjects and scored on the validation
subjects only. Score = mean of val Cohen's kappa (4-stage) on the wrist
recording and on the phone-like rendering, averaged over 2 seeds. Ideas that
help on val are combined. Test is touched once, for the final model, and
compared with the shipped baseline's test numbers.

  python3 training/improve_stage.py           # ablation table -> IMPROVEMENTS.md (staging section)
"""
from __future__ import annotations
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from staging_data import OUT as FEATURES, VARIANTS  # noqa: E402
from train_stage import (features, heuristic, evaluate, build_model, export, PHONE_VARIANT,  # noqa: E402
                         DILATIONS, WIDTH)

BASE = dict(sources="all", p_orig=0.3, gamma=0.0, cw_power=0.5, width=WIDTH, dilations=DILATIONS,
            epochs=80, hmm=False)


def load():
    d = np.load(FEATURES, allow_pickle=True)
    return {k: d[k] for k in ("split", "raw", "stage", "valid", "source")}


def fit(D, cfg, seed):
    import torch
    import torch.nn.functional as F
    split, raws, stages, valids, srcs = D["split"], D["raw"], D["stage"], D["valid"], D["source"]
    use = np.ones(len(split), bool) if cfg["sources"] == "all" else (srcs == cfg["sources"])
    tr = np.where((split == "train") & use)[0]
    va = np.where(split == "val")[0]  # always scored on every val night
    counts = np.bincount(np.concatenate([stages[i][stages[i] >= 0] for i in tr]), minlength=4)
    cw = torch.tensor((counts.sum() / (4 * counts)) ** cfg["cw_power"], dtype=torch.float32)
    torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    model = build_model(cfg["width"], cfg["dilations"])
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=1e-3)
    best, best_state = -1.0, None
    for ep in range(cfg["epochs"]):
        model.train()
        order = rng.permutation(tr)
        for b in range(0, len(order), 4):
            batch = order[b:b + 4]
            T = max(len(stages[i]) for i in batch)
            x = torch.zeros(len(batch), 4, T)
            y = torch.full((len(batch), T), -1, dtype=torch.long)
            for j, i in enumerate(batch):
                v = 0 if rng.random() < cfg["p_orig"] else rng.integers(1, len(VARIANTS))
                n = len(stages[i])
                x[j, :, :n] = torch.tensor(features(raws[i][v]))
                yy = stages[i].copy()
                yy[~valids[i]] = -1
                y[j, :n] = torch.tensor(yy)
            lo, lw = model(x)
            m = y >= 0
            logits, target = lo.permute(0, 2, 1)[m], y[m]
            ce = F.cross_entropy(logits, target, weight=cw, reduction="none")
            if cfg["gamma"] > 0:  # focal loss
                pt = torch.softmax(logits, 1).gather(1, target[:, None])[:, 0]
                ce = ce * (1 - pt) ** cfg["gamma"]
            loss = ce.mean() + 0.5 * F.binary_cross_entropy_with_logits(lw[:, 0][m], (target == 0).float())
            opt.zero_grad()
            loss.backward()
            opt.step()
        if (ep + 1) % 4 == 0:
            sv = val_score(model, D, va, cfg, None)
            if sv > best:
                best, best_state = sv, {k: v.clone() for k, v in model.state_dict().items()}
    model.load_state_dict(best_state)
    hmm = fit_hmm(D, tr) if cfg["hmm"] else None
    return model, hmm


def fit_hmm(D, tr):
    """Stage transition matrix + priors from train PSG labels, for Viterbi smoothing."""
    A = np.ones((4, 4))
    for i in tr:
        s = D["stage"][i]
        for a, b in zip(s[:-1], s[1:]):
            if a >= 0 and b >= 0:
                A[a, b] += 1
    A /= A.sum(1, keepdims=True)
    prior = np.bincount(np.concatenate([D["stage"][i][D["stage"][i] >= 0] for i in tr]), minlength=4) + 1.0
    return dict(log_trans=np.log(A).tolist(), log_prior=np.log(prior / prior.sum()).tolist())


def viterbi(logp, hmm):
    """logp (T,4) log posteriors -> best path, with posteriors turned into scaled
    likelihoods (divide by the class prior). Mirrored in stage_model.dart."""
    lt, lp = np.array(hmm["log_trans"]), np.array(hmm["log_prior"])
    em = logp - lp
    T = len(em)
    dp = em[0] + lp
    back = np.zeros((T, 4), int)
    for t in range(1, T):
        cand = dp[:, None] + lt
        back[t] = cand.argmax(0)
        dp = cand.max(0) + em[t]
    path = [int(dp.argmax())]
    for t in range(T - 1, 0, -1):
        path.append(int(back[t][path[-1]]))
    return np.array(path[::-1])


def predict(model, raw, hmm):
    import torch
    model.eval()
    with torch.no_grad():
        lo, _ = model(torch.tensor(features(raw))[None])
    lo = lo[0].T.numpy()
    if hmm is None:
        return lo.argmax(1)
    logp = lo - np.log(np.exp(lo - lo.max(1, keepdims=True)).sum(1, keepdims=True)) - lo.max(1, keepdims=True)
    return viterbi(logp, hmm)


def scores(model, D, ids, hmm, variant):
    return evaluate([predict(model, D["raw"][i][variant], hmm) for i in ids],
                    [D["stage"][i] for i in ids], [D["valid"][i] for i in ids])


def val_score(model, D, va, cfg, hmm):
    return float(np.mean([scores(model, D, va, hmm, v)["kappa4"] for v in (0, PHONE_VARIANT)]))


def run(D, cfg, seeds=(0, 1)):
    va = np.where(D["split"] == "val")[0]
    out = []
    for sd in seeds:
        model, hmm = fit(D, cfg, sd)
        w, p = scores(model, D, va, hmm, 0), scores(model, D, va, hmm, PHONE_VARIANT)
        out.append((w["kappa4"], p["kappa4"], w["kappa_sw"], p["kappa_sw"]))
    return np.mean(out, 0)


def main():
    D = load()
    trials = [
        ("baseline (shipped config)", {}),
        ("data: Walch only", dict(sources="walch")),
        ("augmentation: 90% phone-like nights (vs 70%)", dict(p_orig=0.1)),
        ("loss: focal, gamma 2", dict(gamma=2.0)),
        ("loss: full inverse-frequency class weights", dict(cw_power=1.0)),
        ("loss: no class weights", dict(cw_power=0.0)),
        ("arch: width 16", dict(width=16)),
        ("arch: width 48", dict(width=48)),
        ("arch: + dilation 32 (receptive field ±62 min)", dict(dilations=(2, 4, 8, 16, 32))),
        ("post-processing: HMM / Viterbi over stages", dict(hmm=True)),
    ]
    rows, base = [], None
    for name, delta in trials:
        cfg = {**BASE, **delta}
        r = run(D, cfg)
        sc = (r[0] + r[1]) / 2
        base = sc if base is None else base
        rows.append((name, delta, r, sc))
        print(f"{name:52s} val κ4 wrist {r[0]:.3f} phone {r[1]:.3f} | κsw {r[2]:.3f} / {r[3]:.3f} | "
              f"score {sc:.3f} ({sc - base:+.3f})", flush=True)
    # combine every idea that helped by > 0.005, then confirm the combination on val
    kept = [d for n, d, r, sc in rows[1:] if sc - base > 0.005]
    combo = {**BASE}
    for d in kept:
        combo.update(d)
    rc = run(D, combo) if kept else rows[0][2]
    sc_combo = (rc[0] + rc[1]) / 2
    print("combined:", {k: v for d in kept for k, v in d.items()}, f"score {sc_combo:.3f}")
    final_cfg = combo if sc_combo >= max(sc for *_, sc in rows) - 0.005 else \
        {**BASE, **max(rows, key=lambda r: r[3])[1]}
    # final: one model on train (seed 0), test scored once
    model, hmm = fit(D, final_cfg, 0)
    te = np.where(D["split"] == "test")[0]
    final = {c: scores(model, D, te, hmm, v) for c, v in (("wrist", 0), ("phone-like", PHONE_VARIANT))}
    for c, r in final.items():
        print(f"FINAL test {c}: acc={r['acc']:.3f} κ4={r['kappa4']:.3f} κsw={r['kappa_sw']:.3f} "
              f"recall={np.round(r['recall'], 2).tolist()}")
    json.dump(dict(rows=[(n, {k: list(v) if isinstance(v, tuple) else v for k, v in d.items()}, list(map(float, r)),
                          float(sc)) for n, d, r, sc in rows],
                   kept=[{k: list(v) if isinstance(v, tuple) else v for k, v in d.items()} for d in kept],
                   combo_score=float(sc_combo),
                   final_cfg={k: list(v) if isinstance(v, tuple) else v for k, v in final_cfg.items()},
                   final={c: dict(acc=r["acc"], kappa4=r["kappa4"], kappa_sw=r["kappa_sw"],
                                  recall=r["recall"].tolist(), cm=r["cm"].tolist()) for c, r in final.items()}),
              open(os.path.join(HERE, "..", "data", "improve_stage.json"), "w"), indent=1, default=float)
    if "--export" in sys.argv:
        export(model, D["raw"][te[0]][PHONE_VARIANT], hmm)


if __name__ == "__main__":
    main()
