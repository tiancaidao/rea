"""
Snore-signature embedder for "who is snoring": log-mel patch -> L2-normalized
embedding. Trained with triplet loss so same-person snores are close and
different-person snores are far, exactly the design we reverse-engineered
(a small embedding + kNN vote). Our own network, our own data.

We use a 16-D embedding to match what the shipped app actually used (the earlier
128-D guess was wrong — the decompile showed 16-D).

Run:  python3 snore_embedding.py         # trains on synthetic identities, exports ONNX
Needs: torch, onnx.
"""
from __future__ import annotations
from datasets import synth_snore_identity_dataset, N_MELS, N_FRAMES

EMBED_DIM = 16


def build_model():
    import torch
    import torch.nn as nn

    def block(ci, co):
        return nn.Sequential(
            nn.Conv2d(ci, co, 3, padding=1), nn.BatchNorm2d(co), nn.ReLU(), nn.MaxPool2d(2)
        )

    class Embedder(nn.Module):
        def __init__(self, dim):
            super().__init__()
            self.features = nn.Sequential(block(1, 16), block(16, 32), block(32, 64))
            self.proj = nn.Sequential(nn.AdaptiveAvgPool2d(1), nn.Flatten(), nn.Linear(64, dim))

        def forward(self, x):
            z = self.proj(self.features(x))
            return nn.functional.normalize(z, dim=-1)

    return Embedder(EMBED_DIM)


def main(epochs: int = 15):
    import torch
    import torch.nn as nn
    X, pid = synth_snore_identity_dataset(n_people=12, per_person=60, seed=1)
    X_t = torch.tensor(X); pid_t = torch.tensor(pid)
    model = build_model()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    triplet = nn.TripletMarginLoss(margin=0.3)

    def sample_triplets(bs=128):
        anchors, positives, negatives = [], [], []
        for _ in range(bs):
            a = torch.randint(0, len(X_t), (1,)).item()
            same = (pid_t == pid_t[a]).nonzero().flatten()
            diff = (pid_t != pid_t[a]).nonzero().flatten()
            p = same[torch.randint(0, len(same), (1,)).item()]
            n = diff[torch.randint(0, len(diff), (1,)).item()]
            anchors.append(a); positives.append(p.item()); negatives.append(n.item())
        return (X_t[anchors], X_t[positives], X_t[negatives])

    for ep in range(epochs):
        model.train()
        for _ in range(30):
            a, p, n = sample_triplets()
            opt.zero_grad()
            loss = triplet(model(a), model(p), model(n))
            loss.backward(); opt.step()
        # quick eval: same-person cosine should beat different-person cosine
        model.eval()
        with torch.no_grad():
            a, p, n = sample_triplets(256)
            za, zp, zn = model(a), model(p), model(n)
            pos = (za * zp).sum(1).mean().item()
            neg = (za * zn).sum(1).mean().item()
        print(f"epoch {ep+1:2d}  cos_same={pos:.3f}  cos_diff={neg:.3f}")

    dummy = torch.zeros(1, 1, N_MELS, N_FRAMES)
    torch.onnx.export(model, dummy, "snore_embedding.onnx", dynamo=False,
                      input_names=["mel"], output_names=["embedding"],
                      dynamic_axes={"mel": {0: "batch"}, "embedding": {0: "batch"}})
    print(f"exported snore_embedding.onnx  (dim={EMBED_DIM})")


if __name__ == "__main__":
    try:
        main()
    except ImportError:
        print("torch not installed — run on a machine with torch+onnx.")
