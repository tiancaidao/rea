"""Post-processing variants for the stager, scored on val only with the baseline
models (2 seeds): Viterbi without prior scaling, and moving-average smoothing of
the stage posteriors. Appends to data/improve_stage.json."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from improve_stage import load, fit, fit_hmm, BASE, PHONE_VARIANT  # noqa: E402
from train_stage import features, evaluate  # noqa: E402


def posts(model, raw):
    import torch
    model.eval()
    with torch.no_grad():
        lo, _ = model(torch.tensor(features(raw))[None])
    lo = lo[0].T.numpy()
    p = np.exp(lo - lo.max(1, keepdims=True))
    return p / p.sum(1, keepdims=True)


def viterbi_plain(p, hmm):
    lt, em = np.array(hmm["log_trans"]), np.log(p + 1e-9)
    dp, back = em[0].copy(), np.zeros((len(p), 4), int)
    for t in range(1, len(p)):
        c = dp[:, None] + lt
        back[t], dp = c.argmax(0), c.max(0) + em[t]
    path = [int(dp.argmax())]
    for t in range(len(p) - 1, 0, -1):
        path.append(int(back[t][path[-1]]))
    return np.array(path[::-1])


def smooth(p, k):
    ker = np.ones(k) / k
    return np.stack([np.convolve(p[:, c], ker, mode="same") for c in range(4)], 1).argmax(1)


D = load()
va = np.where(D["split"] == "val")[0]
tr = np.where(D["split"] == "train")[0]
methods = {"argmax (baseline)": lambda p, h: p.argmax(1), "Viterbi, no prior scaling": viterbi_plain,
           "posterior moving average, 3 epochs": lambda p, h: smooth(p, 3),
           "posterior moving average, 5 epochs": lambda p, h: smooth(p, 5)}
res = {m: [] for m in methods}
for seed in (0, 1):
    model, _ = fit(D, BASE, seed)
    hmm = fit_hmm(D, tr)
    for m, f in methods.items():
        k = [evaluate([f(posts(model, D["raw"][i][v]), hmm) for i in va], [D["stage"][i] for i in va],
                      [D["valid"][i] for i in va])["kappa4"] for v in (0, PHONE_VARIANT)]
        res[m].append(k)
out = {m: np.mean(v, 0).tolist() for m, v in res.items()}
for m, (w, p) in out.items():
    print(f"{m:40s} val κ4 wrist {w:.3f} phone {p:.3f} score {(w + p) / 2:.3f}")
j = json.load(open(os.path.join(HERE, "..", "data", "improve_stage.json")))
j["post"] = out
json.dump(j, open(os.path.join(HERE, "..", "data", "improve_stage.json"), "w"), indent=1)
