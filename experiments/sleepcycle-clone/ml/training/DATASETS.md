# Datasets for the snore / sound-event model

Every source below was checked on 2026-10-21. Only openly-licensed audio is
used. Raw audio sits in the gitignored `ml/data/` and is deleted after feature
caching (`prepare_data.py --prune`). Nothing here, and no model trained from
it, is committed. No Sleep Cycle weights, outputs or user data are used.

## Used

| dataset | licence | what we take | size | split |
|---|---|---|---|---|
| [ESC-50](https://github.com/karolpiczak/ESC-50) (Piczak 2015) | **CC BY-NC 3.0** | snoring (40 clips), coughing (40), and the other 48 classes grouped as bedroom negatives | 600 MB zip | folds 1-3 / 4 / 5 |
| [FSD50K](https://zenodo.org/records/4060432) via the per-file HF mirror [Fhrozen/FSD50k](https://huggingface.co/datasets/Fhrozen/FSD50k) | dataset CC BY 4.0; **only clips individually CC0 or CC BY 3.0** (no BY-NC, no Sampling+) | 768 clips ≤ 1.5 MB: cough, rain/water, wind, fan/appliance, music, traffic, rustle/movement, breathing/sigh, animals (incl. purr), clock. Clips with any speech label are excluded | ~400 MB | dev train / dev val / eval |
| [Mini LibriSpeech](https://www.openslr.org/31/) dev-clean-2 | CC BY 4.0 | read speech, ≤ 2 patches per utterance | 126 MB | speakers hashed 60/20/20 |
| [EPFL edge-AI cough count](https://github.com/esl-epfl/edge-ai-cough-count) via [HF mirror](https://huggingface.co/datasets/szzs1693/edge-ai-cough-count) | CC BY 4.0 | val split (2 subjects): timestamped coughs, plus laugh / deep breathing / throat-clearing trials as negatives | 118 MB | subject A train / subject B test |
| [APSAA — Audio-Polygraphy Dataset for Sleep Apnea Analysis](https://zenodo.org/records/14096541) (Gonzalez-Martinez et al., Univ. of Jaén / Hospital Dr. Sagaz) | tagged CC BY 4.0 on Zenodo, **but the record's terms say: academic and non-commercial use only, no redistribution, cite the source**. We follow the stricter terms. **Status: on hold.** Acceptance was relayed by the project assistant but hasn't reached this machine from Ray directly, so APSAA is not used in the shipped model. The loader is in place for when he confirms | 32 patients' full-night audio (4 kHz mono, synchronised with a polygraph). Snore: 1-s windows inside the technicians' manual "Snore" annotations (≤ 250 per patient). Other: 5-window blocks ≥ 15 s from any snore annotation where the polygraph snore channel is at baseline (`apsaa_overnight` group) | 3.9 GB zip | **by patient**: 20 train / 6 val / 6 test |
| synthetic (ours) | — | room tone (coloured noise at −80…−45 dBFS, sometimes with mains hum). TV = speech + music patches mixed with small-speaker colouring | — | per split |

The per-clip FSD50K licence and uploader (for attribution) are recorded in
`ml/data/fsd50k/selected.csv` when the data is downloaded.

**Commercial note:** the snore weights are **research / non-commercial
only**: ESC-50 is CC BY-NC and APSAA is academic/non-commercial with no
redistribution. Neither the APSAA audio nor anything derived from it is
committed or shared. A shippable model needs commercially-licensed or
self-collected snoring, e.g. the opt-in "Share sounds" (`consent_sounds`)
flywheel.

**APSAA and band-limiting:** APSAA is 4 kHz audio, so after resampling to the
app's 44.1 kHz front-end (polyphase filter) it has no energy above 2 kHz.
Training silences the mel bands above 2 kHz on a random 50% of all the other,
wideband patches, so "no energy above 2 kHz" can't stand in for "snore".
RESULTS.md reports test results separately on full-band open-data snores and
on APSAA patients.

## Considered and not used

| dataset | why not |
|---|---|
| Kaggle "Snoring Dataset" (T. Khan, 500 snore / 500 non-snore) | licence listed as "Unknown". Its own description says the clips were cut from Soundsnap, ZapSplat, Fesliyan Studios and YouTube, which are not redistributable |
| Edge Impulse public project 226454 "Snoring Detection" (996 × 1 s, Apache-2.0 on the page) | appears to be the Kaggle set re-hosted. Its provenance traces to the same non-open sources, so the Apache label can't be relied on |
| AudioSet "Snoring" / "Television" segment lists | labels are CC BY 4.0, but the audio is YouTube video. Downloading it isn't covered by an open licence |
| ICSD (infant cry & snoring) | snoring is extracted from AudioSet (YouTube), same issue |
| UrbanSound8K | CC BY-NC 3.0 and a 6 GB monolithic archive. FSD50K's CC0/CC-BY vehicle and traffic clips cover the traffic group permissively instead |
| MUSAN | 11 GB monolithic archive, no per-file mirror. FSD50K CC0/CC-BY music used instead |

## Attribution

K. J. Piczak, "ESC: Dataset for Environmental Sound Classification", ACM MM 2015 ·
E. Fonseca et al., "FSD50K: an Open Dataset of Human-Labeled Sound Events",
IEEE/ACM TASLP 2022 (and the individual Freesound uploaders listed in
`selected.csv`) · V. Panayotov et al., "LibriSpeech", ICASSP 2015 · L. Orlandic
et al., "A Multimodal Dataset for Automatic Edge-AI Cough Detection", EMBC 2023 ·
F. Gonzalez-Martinez, J. De La Torre-Cruz, J. Carabias-Orti et al., "Polygraph and audio
synchronization applied to apnea event analysis based on non-negative matrix factorization",
EURASIP J. Audio Speech Music Process. 2025, 24 (2025), https://doi.org/10.1186/s13636-025-00410-9 —
APSAA, Zenodo 14096541.

---

# Datasets for the sleep-staging model (Part C)

Motion only: the phone has no heart rate. Checked 2026-10-22.

| dataset | licence | what we take | size | split |
|---|---|---|---|---|
| [Walch et al. 2019, "Motion and heart rate from a wrist-worn wearable and labeled sleep from polysomnography"](https://physionet.org/content/sleep-accel/1.0.0/) (PhysioNet sleep-accel 1.0.0) | **Open Data Commons Attribution 1.0 (ODC-By)** | `motion/<id>_acceleration.txt` (Apple Watch accelerometer, ~50 Hz, g) and `labels/<id>_labeled_sleep.txt` (30-s PSG stages: 0 wake, 1-2 → light, 3-4 → deep, 5 REM). Heart rate is not used | 31 subjects, ~1.5 GB of motion files | subjects 60 / 20 / 20 |
| [Newcastle polysomnography and accelerometer data](https://zenodo.org/records/1160410) (van Hees et al. 2018) | **CC BY 4.0** | GENEActiv wrist accelerometer + PSG scoring | 963 MB zip | (see STAGING_RESULTS.md for whether it was used) |

## Not used

| dataset | why not |
|---|---|
| MESA, SHHS (NSRR) | need an NSRR data-access request and a signed data-use agreement, so they aren't open downloads. Worth requesting later: thousands of nights with actigraphy (MESA) and PSG |

## Attribution

O. Walch, Y. Huang, D. Forger, C. Goldstein, "Sleep stage prediction with raw acceleration and
photoplethysmography heart rate data derived from a consumer wearable device", SLEEP 42(12), 2019;
PhysioNet (Goldberger et al., Circulation 2000) · V. T. van Hees et al., "Estimating sleep parameters
using an accelerometer without sleep diary", Scientific Reports 8, 2018.
