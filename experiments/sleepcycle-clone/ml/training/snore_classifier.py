"""
Snore sound classifier: log-mel patch -> sound class (silence/snore/speech/noise).

A compact 2D-CNN over a (1, 64, 86) log-mel patch — the same family of model as
the reverse-engineered sound-event detector, but our own network and our own
(synthetic or public) training data. Emits per-frame / clip probabilities that
feed sleep_core's snore event post-processing.

Run:  python3 snore_classifier.py       # trains on synthetic mel patches, exports ONNX
Needs: torch, onnx. Point datasets.py at ESC-50 / AudioSet / your own clips for real training.
"""
from __future__ import annotations
from datasets import synth_sound_dataset, CLASSES, N_MELS, N_FRAMES


def build_model(n_classes: int = len(CLASSES)):
    import torch.nn as nn

    def block(ci, co):
        return nn.Sequential(
            nn.Conv2d(ci, co, 3, padding=1), nn.BatchNorm2d(co), nn.ReLU(),
            nn.MaxPool2d(2), nn.Dropout(0.1),
        )

    class SnoreCNN(nn.Module):
        def __init__(self, n_classes):
            super().__init__()
            self.features = nn.Sequential(block(1, 16), block(16, 32), block(32, 64))
            self.head = nn.Sequential(
                nn.AdaptiveAvgPool2d(1), nn.Flatten(), nn.Linear(64, n_classes)
            )

        def forward(self, x):
            return self.head(self.features(x))

    return SnoreCNN(n_classes)


def main(epochs: int = 12):
    import torch
    import torch.nn as nn
    model = build_model()
    Xtr, ytr = synth_sound_dataset(2000, seed=1)
    Xva, yva = synth_sound_dataset(400, seed=2)
    Xtr_t, ytr_t = torch.tensor(Xtr), torch.tensor(ytr)
    Xva_t, yva_t = torch.tensor(Xva), torch.tensor(yva)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    lossf = nn.CrossEntropyLoss()
    for ep in range(epochs):
        model.train()
        perm = torch.randperm(len(Xtr_t))
        for i in range(0, len(perm), 128):
            idx = perm[i:i + 128]
            opt.zero_grad()
            loss = lossf(model(Xtr_t[idx]), ytr_t[idx])
            loss.backward(); opt.step()
        model.eval()
        with torch.no_grad():
            acc = (model(Xva_t).argmax(1) == yva_t).float().mean().item()
        print(f"epoch {ep+1:2d}  val_acc={acc:.3f}")

    dummy = torch.zeros(1, 1, N_MELS, N_FRAMES)
    torch.onnx.export(model, dummy, "snore_classifier.onnx", dynamo=False,
                      input_names=["mel"], output_names=["logits"],
                      dynamic_axes={"mel": {0: "batch"}, "logits": {0: "batch"}})
    print(f"exported snore_classifier.onnx  (classes={CLASSES})")


if __name__ == "__main__":
    try:
        main()
    except ImportError:
        print("torch not installed — run this on a machine with torch+onnx. "
              "Model definition and training loop are ready as-is.")
