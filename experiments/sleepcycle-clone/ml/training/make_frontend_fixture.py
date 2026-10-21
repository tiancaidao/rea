"""
Write flutter_app/test/fixtures/snore_frontend_parity.json: the log-mel patch
ml/audio_pipeline.py computes for a deterministic synthetic signal, so the
Dart front-end (lib/sensing/snore_model.dart) is tested against the exact
Python front-end the model was trained with. Synthetic audio only — no data.

  python3 training/make_frontend_fixture.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import numpy as np  # noqa: E402
from audio_pipeline import SAMPLE_RATE, WINDOW_SAMPLES, N_FRAMES, logmel_frames  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "flutter_app", "test", "fixtures", "snore_frontend_parity.json")


def signal():
    # keep in sync with syntheticPcm() in flutter_app/test/snore_model_test.dart
    n = np.arange(WINDOW_SAMPLES, dtype=np.float64)
    t = n / SAMPLE_RATE
    x = (0.3 * np.sin(2 * np.pi * 150 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t))
         + 0.05 * np.sin(2 * np.pi * 2500 * t)
         + 0.01 * ((n * 7919) % 1000 / 1000 - 0.5))
    return x.astype(np.float32)


if __name__ == "__main__":
    lm = logmel_frames(signal())[:N_FRAMES]
    json.dump({"frames": int(lm.shape[0]), "mels": int(lm.shape[1]),
               "logmel": [round(float(v), 5) for v in lm.flatten()]}, open(OUT, "w"), separators=(",", ":"))
    print("wrote", os.path.normpath(OUT), lm.shape)
