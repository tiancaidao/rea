"""
Sleep-staging model: per-epoch features -> {deep, light, rem, awake}.

Mirrors the architecture we reverse-engineered (a small model over
breathing + movement features per 30 s epoch), but it's our own network trained
on our own / synthetic data. Trains with PyTorch and exports to ONNX (then
convertible to TFLite / CoreML for on-device use).

Run:  python3 stage_model.py            # trains on synthetic nights, writes stage_model.onnx
Needs: torch, onnx (install on your machine if not present).

A dependency-free numpy fallback (logistic regression) is included so the
pipeline still trains and exports *something* when torch isn't available; the
PyTorch path is the real one.
"""
from __future__ import annotations
import numpy as np
from datasets import synth_stage_dataset

STAGES = ["deep", "light", "rem", "awake"]
IN_FEATURES = 3


def train_torch(epochs: int = 20):
    import torch
    import torch.nn as nn
    Xtr, ytr = synth_stage_dataset(40, seed=1)
    Xva, yva = synth_stage_dataset(8, seed=2)
    Xtr_t = torch.tensor(Xtr); ytr_t = torch.tensor(ytr)
    Xva_t = torch.tensor(Xva); yva_t = torch.tensor(yva)

    model = nn.Sequential(
        nn.Linear(IN_FEATURES, 32), nn.ReLU(),
        nn.Linear(32, 32), nn.ReLU(),
        nn.Linear(32, len(STAGES)),
    )
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    lossf = nn.CrossEntropyLoss()
    for ep in range(epochs):
        model.train()
        perm = torch.randperm(len(Xtr_t))
        for i in range(0, len(perm), 256):
            idx = perm[i:i + 256]
            opt.zero_grad()
            loss = lossf(model(Xtr_t[idx]), ytr_t[idx])
            loss.backward(); opt.step()
        with torch.no_grad():
            acc = (model(Xva_t).argmax(1) == yva_t).float().mean().item()
        print(f"epoch {ep+1:2d}  val_acc={acc:.3f}")

    dummy = torch.zeros(1, IN_FEATURES)
    torch.onnx.export(model, dummy, "stage_model.onnx", dynamo=False,
                      input_names=["features"], output_names=["logits"],
                      dynamic_axes={"features": {0: "batch"}, "logits": {0: "batch"}})
    print("exported stage_model.onnx")


def train_numpy_fallback(epochs: int = 300):
    """Softmax regression in numpy -> exports weights to stage_model_npz.npz."""
    Xtr, ytr = synth_stage_dataset(40, seed=1)
    Xva, yva = synth_stage_dataset(8, seed=2)
    n, d = Xtr.shape; k = len(STAGES)
    W = np.zeros((d, k), np.float32); b = np.zeros(k, np.float32)
    Y = np.eye(k, dtype=np.float32)[ytr]
    lr = 0.1
    for ep in range(epochs):
        logits = Xtr @ W + b
        logits -= logits.max(1, keepdims=True)
        p = np.exp(logits); p /= p.sum(1, keepdims=True)
        gW = Xtr.T @ (p - Y) / n
        gb = (p - Y).mean(0)
        W -= lr * gW; b -= lr * gb
    val_logits = Xva @ W + b
    acc = (val_logits.argmax(1) == yva).mean()
    print(f"numpy fallback val_acc={acc:.3f}")
    np.savez("stage_model_npz.npz", W=W, b=b, stages=np.array(STAGES))
    print("exported stage_model_npz.npz")


if __name__ == "__main__":
    try:
        train_torch()
    except ImportError:
        print("torch not available; using numpy fallback")
        train_numpy_fallback()
