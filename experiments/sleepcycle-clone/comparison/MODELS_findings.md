# Recreating Sleep Cycle's models from REA — what's possible, and how

Research note for the REA experiment. Question: can we use the app's encrypted
models, or build our own models that match their performance?

## TL;DR

1. **Using their models — no.** Two of ~10 model files are unencrypted (an FFT
   op and the `snoracle` snore-embedding CNN); the rest are `*.ort.enc`
   (encrypted ONNX Runtime). Decrypting them, running their weights, spoofing
   their client to fetch them, or distilling their outputs are all off the
   table — they defeat a technical protection measure and copy proprietary
   weights, barred by Sleep Cycle's terms and by anti-circumvention law
   (US DMCA §1201; Singapore Copyright Act 2021). A paid trial licenses _use of
   the app_, not the models.
2. **Matching their performance — yes, and the bar is lower than it looks.**
   Independent polysomnography (PSG) studies show phone sleep trackers,
   Sleep Cycle included, are **not** accurate against the medical gold standard.
   So "as good as the original" is achievable with our own models trained on
   data we're allowed to use.

## What "as good as the original" actually means

Peer-reviewed validation, not marketing:

- A 2020 PSG study (21 adults, 2 nights) tested **both the accelerometer and
  microphone versions of Sleep Cycle** against home polysomnography. Finding:
  Sleep Cycle **did not reliably tell sleep from wake, and none of the apps
  could detect REM**. [Journal of Sleep Research / PubMed](https://pubmed.ncbi.nlm.nih.gov/31674096)
- Even the best wrist wearables, which also have heart rate (phones don't), sit
  at **Cohen's κ ≈ 0.5** for 4-stage scoring vs PSG (Apple Watch Series 8
  κ=0.53 in an independent 6-device study). [PMC12038347](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12038347/)
- Apple's own accelerometer+HR classifier reports κ≈0.63; a Google wearable CNN
  (accel+PPG) reports accuracy 0.79 / κ=0.66, and notes **human experts only
  reach ~0.80–0.85 / κ=0.70–0.75** on the same 4-stage task. [Apple (Oct 2025)](https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf) · [Google Research](https://research.google/pubs/sleep-staging-classification-from-wearable-signals-using-deep-learning/)

**Implication:** a phone, with no heart-rate signal, is at the hard end of this
problem. Sleep Cycle's real-world staging is modest, so our bar to "match" it is
modest too. Their genuine strength is the **smart alarm** (wake you in light
sleep near your target) and **snore tracking**, not clinical staging — and both
of those we can reproduce.

## Snore detection — reachable to ~90%+ with public data

This is where we can get genuinely close, legitimately:

- A smartphone snore algorithm (bench test) reported sensitivity 86%,
  specificity 99%, accuracy 95%. [ScienceDirect](https://www.sciencedirect.com/org/science/article/pii/S2561326X25002458)
- A CNN+RNN on sleep-lab audio (18,412 events): accuracy 95.3%, sensitivity
  92.2%, specificity 97.7%, robust to mic placement. [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0169260720317508)
- A smartphone CNN: accuracy 95%, sensitivity 98.6% — but positive predictive
  value only 70%, i.e. **false alarms are the real challenge**, not raw
  accuracy. [arXiv/ResearchGate](https://www.researchgate.net/publication/355903330)

These match the _shape_ of Sleep Cycle's own chain, which REA already revealed.

## What REA legitimately gave us (the architecture, for free)

From the two **unencrypted** files + how the app wires them (already captured in
`experiments/sleepcycle-clone/ml/audio_pipeline.py`):

```
Snore / sound chain (3 models, matches the app):
  raw PCM 44.1 kHz
   → fft_model.tflite        [1,2048] → [1,1025]   (plain FFT, not proprietary)
   → mel filterbank          → 64 mel bins × 86 frames
   → snoracle CNN (tflite)   → 128-D L2-normalized embedding  (plain weights, shape known)
   → compare to per-user snore signature   (snore_signature.ort.enc — encrypted; we DON'T open it)

Staging: sleep_staging / realtime_sleep_staging / staging_inputs (encrypted)
Extras: breathing_rate, gcc_phat_fft (2-sleeper direction), auroracle (general sound)
```

Knowing the _architecture and I/O shapes_ is lawful interface-level RE and is
all we need to build our own. We do **not** read the encrypted weights.

## The plan to reach parity, legitimately

**A. Snore model (start here — testable in days).**

- Rebuild the exact architecture above (our own CNN, same 64×86 mel input,
  128-D embedding) in `ml/training/snore_*.py` (scaffolding already present).
- Train on openly-licensed data: ESC-50 (snoring/cough classes, CC-BY-NC),
  public Kaggle snore-vs-noise sets, AudioSet "Snoring" segments.
- Export to TFLite, run on-device in the `LiveTracker` in place of today's
  loudness proxy. Report sensitivity / specificity / PPV on a held-out set.

**B. Sleep staging model.**

- Small sequence model (TCN/BiLSTM) over per-30-s movement + sound features —
  the same inputs `staging_inputs` consumes.
- Train on public motion+PSG datasets: **Walch 2019** Apple Watch + PSG on
  PhysioNet (open), and **MESA**/**SHHS** via NSRR (free data-access request).
- Target: match the κ≈0.5 band that even wrist wearables live in. Honestly,
  that's parity with the whole category.

**C. Per-user snore signature (their "Who's snoring").**

- Reuse _our_ snore CNN's embeddings + a per-user profile built from clips the
  user confirms/rejects in the Journal. Same idea as snoracle + snore_signature,
  our weights.

**D. Our own data flywheel (the real moat).**

- The backend already has a `consent_sounds` ("Share sounds") field. Add opt-in
  upload of short, user-confirmed snore clips → Cloud Storage → labelled
  training set. This is exactly how Sleep Cycle built its edge: millions of
  consented nights, not a cleverer network.

**E. Benchmark harness (how we prove "as good as").**

- Track the same nights with both apps side by side (phone next to phone).
- Compare our hypnogram / snore-minutes / quality vs the real app's **CSV
  export** (Profile › More › Database). Their outputs grade ours; we never
  train on them.
- Where possible, add a public PSG dataset as true ground truth so we measure
  against the lab, not just against another imperfect app.

## Bottom line for the REA question

"Can we recreate the app from reverse engineering?" — **Almost all of it, yes:**
UX, navigation, backend, and the model _architecture_ are all reproducible from
REA (we've done the first three and captured the fourth). The one thing that
can't be copied lawfully is the **trained weights + labelled data** — and the
evidence says that intelligence, while it's their moat, is only _moderately_
accurate, so we can reach the same league with our own legitimate training.

## Sources

- [Smart sleep tracking through the phone: PSG reliability of four apps (incl. Sleep Cycle)](https://pubmed.ncbi.nlm.nih.gov/31674096)
- [Six wrist wearables vs PSG for sleep staging](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12038347/)
- [Apple — Estimating Sleep Stages from Apple Watch (Oct 2025)](https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf)
- [Google Research — Sleep staging from wearable signals](https://research.google/pubs/sleep-staging-classification-from-wearable-signals-using-deep-learning/)
- [Smartphone-mediated snore detection validation](https://www.sciencedirect.com/org/science/article/pii/S2561326X25002458)
- [Audio-based snore detection using deep neural networks](https://www.sciencedirect.com/science/article/pii/S0169260720317508)
- [Snore detection on smartphone (CNN, low PPV caveat)](https://www.researchgate.net/publication/355903330)
