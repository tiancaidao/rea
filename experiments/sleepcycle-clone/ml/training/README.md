# Model training

Trains the three on-device models the app needs, as **original networks on your
own (or synthetic/public) data** — not the app's encrypted weights, which can't
be used. Each script trains on built-in synthetic data so the pipeline runs and
exports a working model today; swap in real data via `datasets.py` for quality.

| Script | Model | Input → Output | Export |
|---|---|---|---|
| `stage_model.py` | sleep stager | 3 features/epoch → 4 stages | `stage_model.onnx` |
| `snore_classifier.py` | sound classifier | log-mel (1,64,86) → class probs | `snore_classifier.onnx` |
| `snore_embedding.py` | snore signature | log-mel (1,64,86) → 16-D embedding | `snore_embedding.onnx` |

```bash
pip install torch onnx numpy          # on your machine
python3 stage_model.py
python3 snore_classifier.py
python3 snore_embedding.py
```

`stage_model.py` also has a dependency-free numpy fallback so it trains and
exports even without torch.

## Getting real data

- **Snore / sound classes:** ESC-50 (has a `snoring` class), AudioSet, or your
  own labelled clips. Compute 64-bin log-mel with `../audio_pipeline.py` so the
  features match the app at inference time.
- **Who-is-snoring:** record labelled snore clips per person; triplet loss needs
  only identity labels, not alignment.
- **Sleep staging:** an open PSG dataset, or your own accelerometer recordings
  with a morning sleep diary. Features per 30 s epoch: normalized movement,
  normalized breathing rate, breathing confidence.

## On-device conversion

- **Android:** ONNX → TFLite (`onnx2tf` or `onnxruntime` mobile), load with
  `tflite_flutter`/`onnxruntime`.
- **iOS:** ONNX → CoreML (`coremltools`), or run ONNX Runtime / TFLite directly.

The app (`flutter_app/`) consumes these at the two plug-in points: the snore
event detector (`snore_classifier`) and the who-is-snoring kNN
(`snore_embedding`); the stager replaces the heuristic in `sleep_algorithms.dart`.

> These models are trained from scratch on data you control. They are not, and
> must not be, the app's shipped weights (which are AES-GCM encrypted with a
> server-issued key and cannot be extracted from the APK anyway).
