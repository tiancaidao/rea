# sleep_tracker (Flutter)

An original sleep-tracking app in the same category as Sleep Cycle, built from
standard techniques — not a copy of their code or models. It runs a full
analysis pipeline on a **simulated night** out of the box, so you can see the
hypnogram, sleep score and smart-alarm logic with no device or native code.

## Run

```bash
cd flutter_app
flutter pub get
flutter run                 # phone, emulator, or `flutter run -d chrome`
flutter test                # unit tests for the algorithms
```

> This project is authored as source; it wasn't compiled in the environment that
> generated it. If `flutter analyze` flags anything, it'll be a small fix — the
> structure and logic are the substance.

## Structure

```
lib/
  core/sleep_algorithms.dart   # movement, staging, smart alarm, snore (Dart port of sleep_core)
  data/models.dart             # SleepSession, PhasePoint, AlarmSettings
  data/api_client.dart         # client for ../mock-api
  sensing/sleep_tracker.dart   # orchestrates a night; SimulatedNight source for dev
  ui/                          # home, sleep session, results (hypnogram), alarm settings
test/sleep_algorithms_test.dart
```

The analysis is plain Dart and has no device dependency. Real sensing is the one
native piece: swap `SimulatedNight` for a platform-channel source backed by
CoreMotion/AVAudioEngine (iOS) and SensorManager/AudioRecord (Android), and feed
your own trained sound model's frame probabilities into the snore detector.

## How close is this to Sleep Cycle?

Honest, feature-by-feature. "Design parity" = same approach, our own code/params.
"Gap" = real product work still needed.

| Area | Sleep Cycle | This app | Status |
|---|---|---|---|
| Movement tracking | accelerometer, calibrated, per-minute events | accelerometer aggregator, calibration, 30 s epochs | **Design parity** (needs real sensor feed) |
| Sleep staging | learned model (breathing+movement) → 4 stages, smoothed | transparent movement→depth heuristic, Gaussian-smoothed, 4 stages | Baseline; **gap**: train a real model |
| Smart alarm | per-night learned thresholds, eased window, multi-trigger | per-night percentile thresholds, eased window | **Design parity** |
| Snore detection | 30-class sound-event model + event rules | event rules ready; **you plug in the model** | Rules parity; **gap**: your sound model |
| "Who is snoring" | 16-D embedding + kNN vote | kNN vote ready; **you plug in the embedder** | Rules parity; **gap**: your embedding model |
| Hypnogram + score | polished native charts | Flutter hypnogram + simple score | Functional; **gap**: visual polish |
| Audio playback / sleep aid | ExoPlayer library + content | — | **gap** |
| Accounts / cloud sync | Ory + GCP backend | mock API only | **gap**: real backend |
| Wear OS / HealthKit | yes | — | **gap** |
| Paywall / billing | dynamic server-driven | — | **gap** |

**Summary:** the *analysis engine* (movement → stages → smart alarm → snore
post-processing) reaches design parity and runs today on simulated data. The two
real gaps that decide how close you get are (1) your own trained ML models for
staging and snore, and (2) the native sensing + background service per platform.
Everything else (backend, audio content, wearables, billing) is standard product
build-out, not reverse-engineering.
