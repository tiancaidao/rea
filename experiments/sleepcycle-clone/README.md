# sleepcycle-clone (experiment)

A **client-first rebuild scaffold** derived from a read-only reverse-engineering
pass on the Sleep Cycle Android app (`com.northcube.sleepcycle` 4.26.37), using
REA-style workflows. The goal is to see how far an agent + RE can get toward
reconstructing an app's architecture — **not** to copy Northcube's code, trained
models, or brand assets.

> **Scope / ethics.** Everything here is our own implementation of a
> _re-derived design_. No decompiled source, trained weights, or encrypted
> models from the original are included. Two of the original's ML models are
> AES-GCM encrypted (keys in a native lib) specifically to prevent lifting; we
> don't touch them. You train your own weights and run your own backend.

## What's here

| Path                                        | What it is                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `flutter_app/`                              | **The app.** Original Flutter sleep tracker (iOS + Android): tracking, hypnogram + score, smart-alarm settings, sign-in, sleep-aid, paywall; native accelerometer platform channel (Kotlin + Swift). Runs on a simulated night out of the box.                                                                                                                                             |
| `flutter_app/android/wear/`                 | **Wear OS companion** (Kotlin + Compose for Wear): start/stop the night, snooze/stop the alarm, Automatic/Melody/Vibrate alarm type (silent wake-up), Snore Alert buzz. Talks to the phone app over the Wearable Data Layer (`WearPlugin.kt` on the phone). Build with `cd flutter_app/android && ./gradlew :wear:assembleDebug`, install on a paired watch with `adb -s <watch> install`. |
| `backend/api/src/paywalls.json`             | **Server-driven paywalls**: ten variants as module lists and the per-placement A/B split, served by `GET /v1/paywall`; override in Firestore at `config/paywalls`. The app bundles the same file as its offline fallback.                                                                                                                                                                  |
| `sleep_core/`                               | **Original** sleep-tracking algorithms (movement, staging, smart alarm, snore events) from standard techniques — not ported. Plain Python with tests.                                                                                                                                                                                                                                      |
| `ml/training/`                              | Trains your **own** models (sleep stager, snore classifier, 16-D snore-signature embedder) in PyTorch → ONNX, on synthetic or your own data. Runnable.                                                                                                                                                                                                                                     |
| `mock-api/`                                 | Zero-dependency mock backend (token auth, persisted sessions, computed insights, paywall, sleep-aid catalog).                                                                                                                                                                                                                                                                              |
| `ml/audio_pipeline.py`                      | Reference audio front-end (PCM → FFT → mel → CNN tensor) at the **exact shapes** read from the app's unencrypted TFLite models. Runnable.                                                                                                                                                                                                                                                  |
| `mock-api/server.js`                        | Zero-dependency Node mock backend mirroring the app's endpoint shape (Ory-style auth, session upload, insights, remote config/paywall). Runnable.                                                                                                                                                                                                                                          |
| `android/.../net/SleepCloudApi.kt`          | Retrofit interface mapped to the mock API.                                                                                                                                                                                                                                                                                                                                                 |
| `android/.../data/SleepModels.kt`           | DTOs + sleep-phase model.                                                                                                                                                                                                                                                                                                                                                                  |
| `android/.../sensing/MovementDetector.kt`   | Accelerometer detector with calibration, modelled on `logic.detector.MovementDetector`.                                                                                                                                                                                                                                                                                                    |
| `android/.../ml/SnoreEmbedder.kt`           | On-device embedder interface at the RE'd tensor contract.                                                                                                                                                                                                                                                                                                                                  |
| `android/.../domain/SleepPhaseEstimator.kt` | Transparent movement+snore → phase + smart-alarm heuristic.                                                                                                                                                                                                                                                                                                                                |

The `android/` Kotlin files are a **skeleton** to drop into an Android Studio
Compose project — they encode the reconstructed contracts, not a full app.

## Reverse-engineered contracts this scaffold is built on

**On-device ML pipeline** (from the app's `assets/`, runtimes `libtensorflowlite_jni.so` + `libonnxruntime.so`):

```
PCM @ 44100 Hz
  → fft_model.tflite          in [1,2048]      → out [1,1025]   (real-FFT magnitudes)
  → audio_to_mel_spectrogram.ort.enc  (ENCRYPTED; reproduced as a mel filterbank)  → 86×64 log-mel
  → snoracle-*.tflite         in [1,1,86,64]   → out [1,1,128]  (triplet-loss embedding)
  → snore_signature.ort.enc   (ENCRYPTED; reproduced as cosine match vs. a per-user signature)
```

The middle `.tflite` is a **PyTorch CNN** (7× Conv2d+BatchNorm+Dropout) exported via MLIR.

**Sensing** (from `logic.detector`, `sleepanalysis`, confirmed `SensorManager` usage):
accelerometer `MovementDetector` with a calibration phase; `AmbientLightSensor`
(TYPE_LIGHT) for room-dark context; tap + pickup detectors for snooze.

**Backend** (Retrofit2/OkHttp in DEX): Ory Kratos + Hydra auth, GCP Cloud Run
services (`teratron` upload, `syndicate` insights, `trex`, `paradroid`),
Firebase (`mdlabs-sleepcycle`), remote config + dynamic paywalls. Analytics via
Amplitude/Braze/Adjust. Requests are natively signed in the original — implement
your own signing, don't reuse theirs.

Full analysis: `/mnt/project-files/SleepCycle-analysis/` (blueprint + reports).

## Building your own (not a clone)

`sleep_core/` is an **original, clean-room** implementation of the _category's_
standard algorithms, with our own parameters — informed by the reverse-engineered
architecture, but written from scratch, not copied. It is the foundation you build
a real product on; you supply your own trained ML models for the stages below.

- `movement.py` — accelerometer movement detection (50 Hz, 30 s epochs) + calibration.
- `sleep_stages.py` — per-epoch features → AWAKE/REM/LIGHT/DEEP, Gaussian-smoothed.
- `smart_alarm.py` — wake-window firing with thresholds learned from the night's movement.
- `snore.py` — snore event post-processing over your model's scores + a kNN "who is snoring" vote.

### Platform choice (targeting iOS + Android)

The sensing + on-device ML is inherently native on each platform and cannot be
shared by any framework:

| Concern      | iOS                                         | Android                                |
| ------------ | ------------------------------------------- | -------------------------------------- |
| Motion       | CoreMotion (`CMMotionManager`)              | `SensorManager` accelerometer          |
| Audio        | AVAudioEngine + background `AVAudioSession` | `AudioRecord` + mic foreground service |
| On-device ML | CoreML (or ONNX/TFLite iOS)                 | TFLite / ONNX Runtime                  |
| Health       | HealthKit (`sleepAnalysis`)                 | Health Connect                         |

Recommended shape: **Flutter** for the shared app (UI, onboarding, stats, journal,
paywall, networking) + a thin native sensing/ML module per platform. The
`sleep_core` algorithms are plain math and port directly to Dart. Kotlin
Multiplatform is the alternative if you want fully native UI.

## Run it

```bash
# original algorithms: tests + a synthetic-night demo (no deps)
cd sleep_core && python3 test_sleep_core.py

# mock backend
cd mock-api && node server.js        # http://127.0.0.1:8787

# ML front-end smoke test (needs numpy)
cd ml && python3 audio_pipeline.py   # prints shapes: 86×64 → 128-D

# Android: create a Compose app in Android Studio, add the kotlin/ package,
# add retrofit + a tflite/onnxruntime dependency, point baseUrl at
# http://10.0.2.2:8787 (emulator → host mock API).
```

## Next tiers (need the real device / its tools)

- **jadx decompile** of `logic.detector` / `logic.snore` / `sleepstaging` to read the exact scoring math (run REA with a jadx JAR on the Mac host).
- **Hopper/Ghidra** on `libsigner.so` to understand model decryption + request signing (to design your own equivalent).
- **mitmproxy / frida** on a device to capture the live API request/response bodies — the cleanest way to finalize the backend contract.
