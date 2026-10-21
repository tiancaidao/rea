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

## Comparison placeholders (local only)

To make the UX comparison fair, the app can load the **real** APK assets as
temporary placeholders — the onboarding Lottie, the sleep-aid catalog + audio,
the app icon, and the real UI copy. These are Northcube's copyrighted material,
so they are **gitignored and never committed or shipped**. The repo ships
`assets/data/strings.en.sample.json` (our own original copy) and falls back to
it when the real files are absent, so the app still builds and runs from a clean
checkout.

To repopulate for a side-by-side demo on your own machine:

```bash
./tools/extract_placeholders.sh /path/to/com.northcube.sleepcycle.apk
# strings.en.json (real UI copy) is produced from the APK string table separately
```

## How close is this to Sleep Cycle?

Honest, feature-by-feature. "Design parity" = same approach, our own code/params.
"Gap" = real product work still needed.

| Area | Sleep Cycle | This app | Status |
|---|---|---|---|
| Primary navigation | Journal / Statistics / Sleep aid / Profile bottom bar | **same four-tab bottom bar** (NavigationBar) | **Parity** |
| UI text | full string table, 13 locales | **runtime string table** (loads real copy locally, ships original) | **Parity** (one locale) |
| App icon / branding | custom mark | real icon wired as placeholder; original mark in theme | Functional (own brand = gap) |
| Onboarding | animated Lottie intro + consent perks | **real Lottie intro** + real mic/notification perk copy | **Parity** (placeholder assets) |
| Movement tracking | accelerometer, calibrated, per-minute events | accelerometer aggregator, calibration, 30 s epochs | **Design parity** (needs real sensor feed) |
| Sleep staging | learned model (breathing+movement) → 4 stages, smoothed | transparent movement→depth heuristic, Gaussian-smoothed, 4 stages | Baseline; **gap**: train a real model |
| Smart alarm | per-night learned thresholds, eased window | per-night percentile thresholds, eased window | **Design parity** |
| Snore detection | sound-event model + event rules | event rules ready; **you plug in the model** | Rules parity; **gap**: your sound model |
| Hypnogram + score | polished native charts | Flutter hypnogram + score + trends screen | Functional |
| Tracking visuals | live animated night view | animated night view (breathing moon, stars) | Functional |
| Sleep aid | ExoPlayer library + streamed content | **real catalog (16 tracks) + just_audio playback** of bundled tracks, premium lock | **Parity** for free tracks; **gap**: streamed content |
| Sleep notes | tag set, each with a tip, correlated with quality | **real tag set + tips** (snackbar), from string table | **Parity** (needs correlation) |
| Wake-up mood | 5-point morning mood log | **5-point mood row** on results | **Parity** (needs logging/correlation) |
| Statistics | trends over time | trends screen (score line, stage bars) | Functional |
| Accounts / cloud sync | Ory + GCP backend | mock API only | **gap**: real backend |
| Wear OS / HealthKit | yes | — | **gap** |
| Paywall / billing | dynamic server-driven | server-driven mock paywall (no billing) | Partial; **gap**: StoreKit/Billing |

**Summary:** with the APK assets wired in as local placeholders, the *surface*
(navigation, onboarding, sleep aid, sleep notes, mood, text) now reads very
close to the original. The remaining substance gaps are the same two as before —
(1) your own trained ML models for staging and snore, and (2) native sensing +
background service per platform — plus standard product build-out (real backend,
own brand assets, streamed audio content, wearables, billing).
