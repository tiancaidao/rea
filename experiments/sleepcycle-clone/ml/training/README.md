# Model training

Trains the three on-device models the app needs, as **original networks on your
own (or synthetic/public) data** — not the app's encrypted weights, which can't
be used. Each script trains on built-in synthetic data so the pipeline runs and
exports a working model today; swap in real data via `datasets.py` for quality.

| Script                               | Model                                           | Input → Output                     | Export                                                              |
| ------------------------------------ | ----------------------------------------------- | ---------------------------------- | ------------------------------------------------------------------- |
| `stage_model.py`                     | sleep stager                                    | 3 features/epoch → 4 stages        | `stage_model.onnx`                                                  |
| `snore_classifier.py`                | sound classifier (model definition)             | log-mel (1,86,64) → class probs    | —                                                                   |
| `prepare_data.py` + `train_snore.py` | **snore / cough / speech / other on open data** | log-mel (1,86,64) → 4 classes      | `snore_classifier.onnx`, `flutter_app/assets/models/snore_cnn.json` |
| `snore_embedding.py`                 | snore signature                                 | log-mel (1,64,86) → 16-D embedding | `snore_embedding.onnx`                                              |

```bash
pip install torch onnx numpy          # on your machine
python3 stage_model.py
python3 snore_classifier.py
python3 snore_embedding.py
```

`stage_model.py` also has a dependency-free numpy fallback so it trains and
exports even without torch.

## Snore model on open data (current)

```bash
python3 -m venv .venv && .venv/bin/pip install torch onnx onnxruntime numpy soundfile pyarrow
.venv/bin/python -I training/prepare_data.py --download   # ESC-50, FSD50K (CC0/CC-BY clips), LibriSpeech, EPFL cough
.venv/bin/python -I training/prepare_data.py              # -> data/features.npz (grouped negatives, capped)
.venv/bin/python -I training/prepare_data.py --selftest   # held-out clips for the on-device test
.venv/bin/python -I training/train_snore.py               # train, pick threshold on val, export, RESULTS.md
.venv/bin/python -I training/make_frontend_fixture.py     # Dart/Python front-end parity fixture
.venv/bin/python -I training/prepare_data.py --prune      # delete raw audio, keep the feature cache
```

Licences and the rejected sources are in `DATASETS.md`, metrics in
`RESULTS.md`. The app picks the model up from `assets/models/snore_cnn.json`
when built with `--dart-define=SNORE_MODEL=true`.

## Sleep-staging model on open data (Part C)

```bash
.venv/bin/python -I training/staging_data.py   # Walch (PhysioNet) + Newcastle (Zenodo) -> data/staging_features.npz
.venv/bin/python -I training/train_stage.py    # train, compare with the heuristic, export, STAGING_RESULTS.md
```

The app picks it up from `assets/models/stage_tcn.json` when built with
`--dart-define=STAGE_MODEL=true`.

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
