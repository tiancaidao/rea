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
| synthetic (ours) | — | room tone (coloured noise at −80…−45 dBFS, sometimes with mains hum). TV = speech + music patches mixed with small-speaker colouring | — | per split |

The per-clip FSD50K licence and uploader (for attribution) are recorded in
`ml/data/fsd50k/selected.csv` when the data is downloaded.

**Commercial note:** ESC-50 is non-commercial, and it supplies all 40 snore
clips. The current snore weights are therefore research-only. A shippable
model needs commercially-licensed or self-collected snoring, e.g. the opt-in
"Share sounds" (`consent_sounds`) flywheel.

## Considered and not used

| dataset | why not |
|---|---|
| Kaggle "Snoring Dataset" (T. Khan, 500 snore / 500 non-snore) | licence listed as "Unknown". Its own description says the clips were cut from Soundsnap, ZapSplat, Fesliyan Studios and YouTube, which are not redistributable |
| Edge Impulse public project 226454 "Snoring Detection" (996 × 1 s, Apache-2.0 on the page) | appears to be the Kaggle set re-hosted. Its provenance traces to the same non-open sources, so the Apache label can't be relied on |
| AudioSet "Snoring" / "Television" segment lists | labels are CC BY 4.0, but the audio is YouTube video. Downloading it isn't covered by an open licence |
| ICSD (infant cry & snoring) | snoring is extracted from AudioSet (YouTube), same issue |
| UrbanSound8K | CC BY-NC 3.0 and a 6 GB monolithic archive. FSD50K's CC0/CC-BY vehicle and traffic clips cover the traffic group permissively instead |
| MUSAN | 11 GB monolithic archive, no per-file mirror. FSD50K CC0/CC-BY music used instead |
| APSAA (Audio-Polygraphy Dataset for Sleep Apnea Analysis, Zenodo 14096541) | real overnight snoring from 32 patients, tagged CC BY 4.0, but the record's text adds "academic and non-commercial use only, no redistribution". That conflict needs a decision before use. It is also a single 3.9 GB zip, and its snore labels are a cannula pressure envelope, not audio annotations |

## Attribution

K. J. Piczak, "ESC: Dataset for Environmental Sound Classification", ACM MM 2015 ·
E. Fonseca et al., "FSD50K: an Open Dataset of Human-Labeled Sound Events",
IEEE/ACM TASLP 2022 (and the individual Freesound uploaders listed in
`selected.csv`) · V. Panayotov et al., "LibriSpeech", ICASSP 2015 · L. Orlandic
et al., "A Multimodal Dataset for Automatic Edge-AI Cough Detection", EMBC 2023.
