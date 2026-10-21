# Sleep-staging model results (Part C)

**Input:** motion only. That's the app's per-30-s movement number (summed |Δ|acceleration| + spikes > 0.03 g at 50 Hz), normalised per night, plus time since start and until the end of the night. **Model:** our own dilated temporal CNN (~17k params, receptive field ±31 min), 4 stages + a wake head, trained from scratch on open data (see `DATASETS.md`). No Sleep Cycle weights or outputs are used.

**Data:** Walch et al. 2019 (PhysioNet sleep-accel, ODC-By 1.0; healthy adults, Apple Watch) and Newcastle 2015 (van Hees, CC BY 4.0; sleep-clinic patients, GENEActiv), wrist accelerometer + PSG, nights split by subject within each source: 35 train / 11 val / 11 test. Train epochs: wake 6063, light 16245, deep 5741, rem 5480. Model chosen on val (epoch 56); test scored once.

**Conditions:** *wrist* = the sensor as recorded. *phone-like* = the same nights with motion attenuated 10×, smoothed and given phone sensor noise. That's a stand-in for a phone on the mattress, which we can't get with PSG labels from open data.

| stager | condition | accuracy | κ 4-stage | κ sleep/wake | κ 4-stage (mean per night) | recall wake / light / deep / REM |
|---|---|---|---|---|---|---|
| our model | wrist | 0.499 | 0.272 | 0.427 | 0.272 | 0.67 / 0.52 / 0.55 / 0.26 |
| current heuristic | wrist | 0.400 | 0.016 | 0.031 | 0.022 | 0.02 / 0.62 / 0.18 / 0.26 |
| our model | phone-like | 0.439 | 0.177 | 0.266 | 0.173 | 0.22 / 0.48 / 0.64 / 0.30 |
| current heuristic | phone-like | 0.400 | -0.033 | -0.008 | -0.022 | 0.08 / 0.70 / 0.01 / 0.16 |

**By test source** (κ 4-stage / κ sleep-wake):

| source | test nights | our model, wrist | our model, phone-like | heuristic, wrist |
|---|---|---|---|---|
| newcastle | 5 | 0.25 / 0.40 | 0.17 / 0.26 | -0.00 / 0.03 |
| walch | 6 | 0.28 / 0.43 | 0.18 / 0.29 | 0.04 / 0.04 |

**Confusion matrix, our model, wrist** (rows = PSG, cols = predicted; wake, light, deep, REM):

```
   980    310     41    122
   804   2734    807    958
    48    629    949     93
   443    728    167    466
```

**Confusion matrix, our model, phone-like** (rows = PSG, cols = predicted; wake, light, deep, REM):

```
   324    553    307    269
   188   2538   1419   1158
    23    482   1106    108
    17    893    345    549
```

**Published reference points** (MODELS_findings.md): phone apps incl. Sleep Cycle do not reliably separate sleep from wake vs PSG. Wrist wearables *with heart rate* reach κ ≈ 0.5 for 4 stages (Apple Watch S8 κ 0.53; Apple's own κ ≈ 0.63; Google accel+PPG κ 0.66). Experts agree at κ ≈ 0.70–0.75. Motion-only staging cannot see REM vs deep directly, so a 4-stage κ well below the heart-rate wearables is expected. Sleep/wake is where motion carries the signal.

<!-- below this line is maintained by hand; train_stage.py keeps it -->
## In the app

`flutter_app/lib/sensing/stage_model.dart` runs the stager in pure Dart.
`LiveTracker.analyze()` uses it when built with `--dart-define=STAGE_MODEL=true`,
the model asset is bundled, and the night is at least 10 minutes long. It reads
the accelerometer epochs only, as trained. Otherwise the app keeps the
heuristic `estimateStages`.

| check (Android emulator `sc_test`, 2026-10-22) | result |
|---|---|
| Dart vs PyTorch logits (`test/stage_model_test.dart`) | max abs diff < 2e-3 |
| Held-out test night (8.0 h, phone-like rendering) replayed through `LiveTracker.addAccelEpoch` → `analyze()` on the device | 958 / 958 epochs agree with PyTorch, staged in **28 ms** |

## Caveats

- The phone-on-mattress domain is simulated (attenuated, smoothed, noised wrist motion). No open
  dataset pairs a phone on the mattress with PSG. The benchmark harness (side-by-side nights) and a
  wearable/PSG reference are how to close that gap.
- Motion-only staging can't see REM vs deep directly. Those come mostly from time-of-night and
  movement patterns, which is why the 4-stage κ trails the heart-rate wearables.
