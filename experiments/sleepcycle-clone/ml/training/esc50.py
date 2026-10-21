"""
ESC-50 loader for the snore/sound classifier.

ESC-50 (Piczak, 2015) is a labelled set of 2000 five-second environmental audio
clips in 50 classes. We map the relevant classes onto our 4-way sound task and
run each clip through the SAME front-end the app uses (ml/audio_pipeline.py:
44.1 kHz -> 2048-pt FFT -> 64 mel bands -> 86-frame log-mel patch).

LICENSE: ESC-50 is Creative Commons Attribution-NonCommercial (CC BY-NC 3.0).
That permits research / non-commercial use with attribution. It is used HERE to
prove the pipeline reaches real-world snore-detection performance. A shippable,
commercial model would need commercially-licensed or self-collected data (e.g.
our own opt-in "Share sounds" clips); see RESULTS.md. We do NOT redistribute the
audio — it is downloaded locally into a gitignored data/ dir.

  python3 training/esc50.py --download      # fetch + unzip into ml/data/ESC-50
  from esc50 import load_esc50 ; X, y = load_esc50()

Attribution: K. J. Piczak, "ESC: Dataset for Environmental Sound
Classification", ACM Multimedia 2015. https://github.com/karoldvl/ESC-50
"""
from __future__ import annotations
import csv
import os
import sys
import urllib.request
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data", "ESC-50")
URL = "https://github.com/karoldvl/ESC-50/archive/master.zip"

# ESC-50 class -> our label. Only mapped classes are used.
CLASS_MAP = {
    "snoring": "snore",
    "coughing": "cough",
    # speech-like / human vocal
    "crying_baby": "speech",
    "laughing": "speech",
    "sneezing": "speech",
    "breathing": "speech",   # vocal/airway, grouped with human sounds here
    # bedroom / ambient "other"
    "clock_tick": "other",
    "clock_alarm": "other",
    "wind": "other",
    "rain": "other",
    "vacuum_cleaner": "other",
    "washing_machine": "other",
    "door_wood_creaks": "other",
    "crackling_fire": "other",
    "water_drops": "other",
    "pouring_water": "other",
}
LABELS = ["snore", "cough", "speech", "other"]


def download(dest: str = DATA) -> str:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.isdir(os.path.join(dest, "audio")):
        return dest
    zip_path = os.path.join(os.path.dirname(dest), "esc50.zip")
    print(f"downloading ESC-50 (~600 MB) -> {zip_path}")
    urllib.request.urlretrieve(URL, zip_path)
    print("unzipping…")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(os.path.dirname(dest))
    extracted = os.path.join(os.path.dirname(dest), "ESC-50-master")
    if os.path.isdir(extracted) and not os.path.isdir(dest):
        os.rename(extracted, dest)
    os.remove(zip_path)
    return dest


def _load_clip(path: str):
    import soundfile as sf
    from audio_pipeline import mel_spectrogram, SAMPLE_RATE

    pcm, sr = sf.read(path, dtype="float32")
    if pcm.ndim > 1:
        pcm = pcm.mean(axis=1)
    if sr != SAMPLE_RATE:
        # linear resample to the app's rate (clips are 5 s; cheap, no scipy dep)
        n = int(len(pcm) * SAMPLE_RATE / sr)
        pcm = np.interp(np.linspace(0, len(pcm) - 1, n), np.arange(len(pcm)), pcm).astype(np.float32)
    return mel_spectrogram(pcm)  # (86, 64)


def load_esc50(folds=(1, 2, 3, 4, 5), data_dir: str = DATA):
    """Return (X [n,1,86,64], y [n], folds [n]). Windows each clip to one patch.
    `folds` selects ESC-50's official cross-validation folds (use 5 as test)."""
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(HERE, ".."))
    meta = os.path.join(data_dir, "meta", "esc50.csv")
    if not os.path.isfile(meta):
        raise FileNotFoundError(f"{meta} not found — run: python3 training/esc50.py --download")
    rows = list(csv.DictReader(open(meta)))
    X, y, f = [], [], []
    for r in rows:
        if r["category"] not in CLASS_MAP:
            continue
        fold = int(r["fold"])
        if fold not in folds:
            continue
        patch = _load_clip(os.path.join(data_dir, "audio", r["filename"]))
        X.append(patch.T[None, :, :])  # (1, 64, 86) to match the CNN tensor
        y.append(LABELS.index(CLASS_MAP[r["category"]]))
        f.append(fold)
    print(f"loaded {len(X)} clips from ESC-50 folds {folds} "
          f"({ {LABELS[i]: y.count(i) for i in range(len(LABELS))} })")
    return np.asarray(X, np.float32), np.asarray(y, np.int64), np.asarray(f, np.int64)


if __name__ == "__main__":
    if "--download" in sys.argv:
        print("ready:", download())
    else:
        X, y, f = load_esc50()
        print("X", X.shape, "y", y.shape)
