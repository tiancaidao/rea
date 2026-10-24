# Improvements pass: what was tried, what it did, what was kept

Rules: each idea is measured, not assumed. Selection uses the validation split
only. The held-out test split is scored once, for the final model, and compared
with the shipped model's test numbers. Same hard rules as before: no Sleep Cycle
weights, no training on its outputs, open data only (APSAA is on hold, see
below), and no third-party pretrained models (YAMNet, PANNs, …).

## Sleep-staging model

**Val score** = mean Cohen's κ (4-stage) on the wrist recording and on the
phone-like rendering, averaged over 2 training seeds (`improve_stage.py`,
`improve_stage_post.py`). 11 val nights, so differences under ~0.01 are noise.

| idea                                                        | val κ4 wrist | val κ4 phone-like | val score | Δ vs baseline | kept?      |
| ----------------------------------------------------------- | ------------ | ----------------- | --------- | ------------- | ---------- |
| baseline (shipped config)                                   | 0.327        | 0.178             | 0.252     | —             | —          |
| data: Walch only (drop Newcastle)                           | 0.246        | 0.167             | 0.207     | −0.045        | no         |
| augmentation: 90% phone-like nights (vs 70%)                | 0.306        | 0.164             | 0.235     | −0.017        | no         |
| loss: focal, γ = 2                                          | 0.329        | 0.170             | 0.249     | −0.003        | no         |
| loss: full inverse-frequency class weights                  | 0.313        | 0.144             | 0.229     | −0.023        | no         |
| loss: no class weights                                      | 0.307        | 0.072             | 0.189     | −0.063        | no         |
| arch: width 16                                              | 0.303        | 0.172             | 0.238     | −0.015        | no         |
| arch: width 48                                              | 0.341        | 0.163             | 0.252     | 0.000         | no         |
| arch: + dilation 32 (receptive field ±62 min)               | 0.337        | 0.175             | 0.256     | +0.004        | no (noise) |
| post: HMM, posteriors ÷ class prior                         | 0.283        | 0.134             | 0.209     | −0.044        | no         |
| post: **Viterbi over stage transitions (no prior scaling)** | 0.340        | 0.185             | 0.263     | **+0.011**    | **yes**    |
| post: posterior moving average, 3 epochs                    | 0.334        | 0.179             | 0.256     | +0.004        | no         |
| post: posterior moving average, 5 epochs                    | 0.333        | 0.180             | 0.257     | +0.005        | no         |

**Test, scored once** (11 held-out nights, κ 4-stage / κ sleep-wake):

| model                                           | wrist             | phone-like      |
| ----------------------------------------------- | ----------------- | --------------- |
| shipped before this pass (argmax)               | 0.272 / 0.427     | 0.177 / 0.266   |
| **after: same network + Viterbi (shipped now)** | **0.284 / 0.465** | 0.177 / 0.264   |
| current app heuristic, for reference            | 0.016 / 0.031     | −0.033 / −0.008 |

Verdict: a small, real gain on wrist-like motion (sleep/wake κ +0.04) and no
change on the phone-like rendering. The network itself is already at what 35
nights of motion-only data supports. More nights, not tuning, is the lever:
MESA via an NSRR access request is the obvious next source. Viterbi is in the
app (`StageModel.viterbi`), and parity is tested against Python.

Not tried: self-training on unlabelled nights (there are no open unlabelled
phone nights; the benchmark harness nights could serve later). Calibration also
wasn't tried: it doesn't change the argmax / Viterbi stages.

## Snore / sound-event model

Trained on the open data plus APSAA (accepted by Ray; research-only).
**Val score** = 0.5 × val snore average precision + 0.5 × val F0.5 at the
val-chosen threshold (`improve_snore.py`, one seed). Val = ESC-50 fold 4 +
held-out speakers/subjects + 6 APSAA patients. Ideas over +0.01 are kept.

| idea                                              | val snore AP | val P / R   | val F0.5 | val score | Δ          | kept?            |
| ------------------------------------------------- | ------------ | ----------- | -------- | --------- | ---------- | ---------------- |
| baseline (shipped config)                         | 0.748        | 0.74 / 0.56 | 0.696    | 0.722     | —          | —                |
| aug: room reverb                                  | 0.746        | 0.75 / 0.54 | 0.693    | 0.720     | −0.003     | no               |
| aug: phone-mic band-limits 3–6 kHz                | 0.754        | 0.77 / 0.54 | 0.706    | 0.730     | +0.008     | no (under +0.01) |
| aug: ±10% time stretch                            | 0.743        | 0.70 / 0.60 | 0.676    | 0.710     | −0.013     | no               |
| aug: ±2-band pitch shift                          | 0.735        | 0.81 / 0.43 | 0.687    | 0.711     | −0.011     | no               |
| hard negatives: clock / breathing / pets drawn 3× | 0.744        | 0.77 / 0.52 | 0.702    | 0.723     | +0.001     | no               |
| loss: focal, γ = 2                                | 0.751        | 0.81 / 0.44 | 0.696    | 0.723     | +0.001     | no               |
| loss: no label smoothing                          | 0.741        | 0.79 / 0.49 | 0.702    | 0.722     | 0.000      | no               |
| arch: wider (24/48/96)                            | 0.760        | 0.71 / 0.60 | 0.688    | 0.724     | +0.002     | no               |
| arch: deeper (16/32/64/64)                        | 0.766        | 0.80 / 0.55 | 0.732    | 0.749     | **+0.027** | candidate → test |

Augmentation (SNR-range background mixing, ±13 dB gain, SpecAugment, time
shift, band-limit balancing) and val-based hard-negative rebalancing were
already in the baseline. The ideas above are what came on top.

**Test, scored once, for the one candidate** (per ~1 s window):

| model                  | all test: AP / P / R | APSAA patients: P / R / FA·h⁻¹ | full-band ESC-50: P / R |
| ---------------------- | -------------------- | ------------------------------ | ----------------------- |
| baseline (**shipped**) | 0.847 / 0.85 / 0.64  | 0.85 / 0.66 / 425              | **0.92 / 0.21**         |
| deeper (16/32/64/64)   | 0.859 / 0.89 / 0.62  | **0.89 / 0.64 / 271**          | 0.60 / 0.05             |

Verdict: **not shipped.** The deeper network is better on 4 kHz hospital
overnight audio, but worse on full-band snores in both precision and recall. A
phone records full-band, and precision is the priority. The ESC-50 test is
only 8 clips, so this is a weak signal, but it points the wrong way and the
model is also twice the size. Revisit once full-band overnight phone recordings
exist (the "Share sounds" flywheel, or the benchmark nights).

### Event-level post-processing (kept)

Scored on continuous audio (`event_eval.py`): 10-minute stretches from APSAA
patients, one decision per second exactly like the app, against the
technicians' snore annotations. 18 stretches from 6 val patients choose the
rule; 18 stretches from 6 test patients are scored once.

| rule (val)                                 | event P | event R | false alarms / h | snore-minutes error per 10 min |
| ------------------------------------------ | ------- | ------- | ---------------- | ------------------------------ |
| per-second threshold, no smoothing         | 0.54    | 0.96    | 256.7            | 1.82                           |
| app before: 3-s majority, ≥ 3 s            | 0.60    | 0.88    | 66.0             | 2.24                           |
| 3-s majority, ≥ 3 s, bridge gaps ≤ 5 s     | 0.56    | 0.95    | 26.7             | 1.94                           |
| 5-s majority, ≥ 3 s                        | 0.61    | 0.86    | 44.0             | 1.99                           |
| **5-s majority, ≥ 5 s, bridge gaps ≤ 5 s** | 0.58    | 0.82    | **24.0**         | **1.35**                       |
| 3-s majority, ≥ 5 s, bridge gaps ≤ 10 s    | 0.52    | 0.86    | 14.7             | 2.01                           |

Kept: **5-s majority, events ≥ 5 s, gaps ≤ 5 s bridged**, the lowest
snore-minutes error with few false alarms. On **test, once**: event recall
0.83, event precision 0.38, 31 false alarms / h, snore-minutes error 1.69 per
10 min (69 annotated episodes). Event precision is low partly because the
technicians annotate episodes while the detector splits and merges them
differently. The minutes error is the number the app shows. The rule is in
`LiveTracker.snoreEvents`, and Dart `detectSnoreEvents` mirrors the Python one
(unit-tested).

### Not tried / blocked

- **Self-training on unlabelled APSAA audio** (pseudo-labels): not run. APSAA's
  annotations already cover the nights, so its "unlabelled" parts are mostly
  non-snore, and pseudo-labelling them risks reinforcing the 12% of hospital
  non-snore windows the model already calls snore. Worth a careful try once there's
  a clean full-band unlabelled set (benchmark nights).
- **Calibration** (temperature scaling): doesn't change any decision. The
  threshold is picked on val after training either way.
- **Third-party pretrained audio models** (YAMNet, PANNs): excluded by Ray.
