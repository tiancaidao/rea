# Night benchmark: our tracker vs the original app

Goal: measure "as good as the original" on **the same nights**. Both apps
track side by side, and the harness compares our output with the original
app's own export.

**Rule:** the original app's export only *grades* ours. It is read by
`benchmark_night.py`, summarised into a report, and never used to train,
tune or distil any model.

## Protocol

1. Put two phones on the nightstand, or one phone per app, same distance from
   the sleeper. Use the same mode in both (microphone, or under-the-sheet
   accelerometer), and start and stop both within a minute of each other.
2. Ours: track with the snore model on
   (`flutter run --dart-define=SNORE_MODEL=true`). In the morning, go to
   Settings › Database › **Export nights for benchmarking (JSON)** →
   `sleep_export.json`.
3. Original app: Profile › More › Database › Export → `sleepdata.csv`.
4. Optional, for epoch-level hypnogram agreement: digitise the original's night
   graph into `their_hypnogram.csv` (`time,stage`, stage ∈ awake/light/deep).
   The CSV export doesn't carry the hypnogram.
5. Optional, for ground truth: a reference hypnogram for the same night
   (`reference_hypnogram.csv`, same format), e.g. a wearable or a sleep-lab
   PSG. Then both apps are scored against it, not just against each other.
6. Run:

```bash
python3 benchmark_night.py --ours sleep_export.json --theirs sleepdata.csv \
    --their-hypnogram their_hypnogram.csv --out report.md
```

Keep the exports and reports out of git (they are personal sleep data).

## What it compares

| quantity | ours (from the JSON) | theirs (CSV column) |
|---|---|---|
| time in bed | session end − start | `Time in bed (seconds)` |
| time asleep | non-wake 30-s epochs | `Time asleep (seconds)` |
| sleep onset latency | first non-wake epoch | `Time before sleep (seconds)` |
| snore time | `snoreMinutes` (model events) | `Snore time (seconds)` |
| score | `sleepScore` | `Sleep Quality` (%) |
| hypnogram | per-epoch stages, REM → light | digitised graph (optional) |

Columns are matched by header name, so the parser tolerates added or reordered
columns and either `;` or `,` as the delimiter. Unmatched columns are listed
in the report.

Nights are paired when they overlap by ≥ 50% of the shorter one. Over all
paired nights it reports bias (ours − theirs), MAE, Bland–Altman 95% limits of
agreement and Pearson r (n ≥ 3), plus agreement and κ on "snored > 5 min".
Hypnograms get 30-s epoch accuracy, Cohen's κ and a wake/light/deep confusion
matrix.

## Targets

From the literature in `MODELS_findings.md`:

- Snore minutes: within the original's night-to-night noise. Aim for MAE
  ≤ 5 min with no systematic bias, and > 90% agreement on "snored > 5 min".
- Time asleep / in bed: |bias| ≤ 10 min. Both apps are movement-based, so
  close agreement is expected.
- Hypnogram: κ ≈ 0.4–0.5 against the original is parity. Phone apps don't
  reliably separate sleep from wake against PSG, and even wrist wearables with
  heart rate sit at κ ≈ 0.5 vs PSG. With a reference hypnogram, compare the two
  apps' κ against it; matching or beating theirs is the real bar.

## Statistical power

One night is a smoke test. Snore minutes and time asleep vary a lot night to
night, so plan **≥ 10 paired nights** (ideally with some snoring and some
quiet nights) before drawing conclusions. The limits of agreement are only
meaningful at that size.

`python3 benchmark_night.py --selftest` builds synthetic files and checks the
harness end to end.
