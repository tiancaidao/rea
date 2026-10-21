"""
Datasets for training the sleep-tracker models.

Two modes:
  - synthetic: self-contained generators so the training scripts run end-to-end
    with no downloads (useful to validate the pipeline and export working models).
  - real: thin loader hooks you point at your own labelled data. For snore audio,
    public options include ESC-50 (has a 'snoring' class) and AudioSet; for sleep
    staging, an open PSG dataset or your own accelerometer recordings with a sleep
    diary. Those are YOUR data choices — none are bundled here.

Everything produces plain numpy arrays so the model scripts stay framework-light.
"""
from __future__ import annotations
import numpy as np

# Audio / mel settings consistent with ml/audio_pipeline.py
SR = 44100
N_MELS = 64
N_FRAMES = 86          # ~1 s window for the snore embedder
CLASSES = ["silence", "snore", "speech", "noise"]  # example 4-class sound set


def _fake_mel(kind: str, rng: np.random.Generator) -> np.ndarray:
    """Return a (N_MELS, N_FRAMES) log-mel patch with class-dependent structure."""
    base = rng.normal(-6, 1.0, size=(N_MELS, N_FRAMES)).astype(np.float32)
    t = np.linspace(0, 1, N_FRAMES)
    if kind == "snore":
        # low-frequency periodic energy (snore ~ 0.3-1 Hz amplitude modulation, low bands)
        amp = (np.sin(2 * np.pi * 0.7 * t * N_FRAMES / 10) ** 2)
        base[:20, :] += 4.0 * amp[None, :]
    elif kind == "speech":
        base[15:45, :] += 3.0 * (rng.random((30, N_FRAMES)) > 0.5)
    elif kind == "noise":
        base += 2.0 * rng.random((N_MELS, N_FRAMES))
    # "silence": leave as low-energy floor
    return base


def synth_sound_dataset(n: int, seed: int = 0):
    """Classification data: (X [n,1,N_MELS,N_FRAMES], y [n])."""
    rng = np.random.default_rng(seed)
    X = np.empty((n, 1, N_MELS, N_FRAMES), np.float32)
    y = np.empty((n,), np.int64)
    for i in range(n):
        c = rng.integers(0, len(CLASSES))
        X[i, 0] = _fake_mel(CLASSES[c], rng)
        y[i] = c
    return X, y


def synth_snore_identity_dataset(n_people: int, per_person: int, seed: int = 0):
    """Embedding data for 'who is snoring': each person has a characteristic
    low-band formant. Returns (X, person_id)."""
    rng = np.random.default_rng(seed)
    X = np.empty((n_people * per_person, 1, N_MELS, N_FRAMES), np.float32)
    pid = np.empty((n_people * per_person,), np.int64)
    centers = rng.integers(3, 18, size=n_people)  # each person's dominant mel band
    k = 0
    for p in range(n_people):
        for _ in range(per_person):
            m = _fake_mel("snore", rng)
            m[centers[p]:centers[p] + 3, :] += 5.0
            X[k, 0] = m
            pid[k] = p
            k += 1
    return X, pid


def synth_stage_dataset(n_nights: int, epochs: int = 960, seed: int = 0):
    """Staging data: per-epoch features (movement, breathing_rate_norm,
    breathing_conf) and a stage label 0..3 (deep/light/rem/awake).

    Generates a plausible night: deep early, cycling into REM, waking at the end,
    with movement anti-correlated to depth. Returns (X [N,3], y [N])."""
    rng = np.random.default_rng(seed)
    Xs, ys = [], []
    for _ in range(n_nights):
        for e in range(epochs):
            frac = e / epochs
            # depth cycles ~90 min; shallower toward morning
            cycle = 0.5 + 0.5 * np.cos(2 * np.pi * e / 180)
            depth = (1 - frac) * cycle            # 1=deep .. 0=shallow
            awake = frac > 0.97 or frac < 0.03 or rng.random() < 0.02
            if awake:
                stage = 3
            elif depth > 0.66:
                stage = 0
            elif depth > 0.33:
                stage = 1
            else:
                stage = 2  # rem in shallow-but-asleep
            movement = (0.8 if stage == 3 else (0.6 - 0.5 * depth)) * rng.random()
            br = rng.normal(14, 2) if stage != 3 else rng.normal(16, 4)
            br_norm = np.clip((br - 10) / 15 * 2 - 1, -1, 1)
            conf = 0.0 if stage == 3 else float(np.clip(rng.normal(0.6, 0.2), 0, 1))
            Xs.append([movement, br_norm, conf])
            ys.append(stage)
    return np.array(Xs, np.float32), np.array(ys, np.int64)
