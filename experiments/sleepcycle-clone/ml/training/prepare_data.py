"""
Build the snore / sound-event training set from openly-licensed public audio.

Every clip goes through the SAME front-end the app runs on-device
(ml/audio_pipeline.py: 44.1 kHz -> 2048-pt FFT -> 64 mel -> 86-frame patch,
~2.02 s per patch) and is cut into patches labelled snore / cough / speech /
other. "other" is a deliberately broad, capped spread of bedroom-night sounds,
each patch tagged with its negative group (rain_water, wind, fan_appliance,
music, tv, traffic, rustle_movement, breathing_nonspeech, animals, clock,
room_tone, misc) so RESULTS.md can report each group's false-positive rate into
"snore". Output: one float16 cache, data/features.npz (gitignored); raw audio
can then be deleted with --prune (it is re-downloadable).

Sources (licences verified 2026-10-21, see DATASETS.md):
  ESC-50               CC BY-NC 3.0        snoring, coughing + 48 classes -> groups
  FSD50K (HF mirror)   CC BY 4.0 overall;  only clips individually CC0 or CC BY 3.0
  Mini LibriSpeech     CC BY 4.0           dev-clean-2 read speech -> speech
  EPFL edge-AI cough   CC BY 4.0           val split, outward mic, cough times
  synthetic            ours                room tone; TV = speech + music mixes

Splits never share a clip / speaker / subject: ESC-50 folds 1-3 train, 4 val,
5 test; FSD50K dev train/val -> train/val, eval -> test; LibriSpeech speakers
hashed 60/20/20; EPFL's two subjects train vs test.

  python3 training/prepare_data.py --download
  python3 training/prepare_data.py            # writes data/features.npz
  python3 training/prepare_data.py --apsaa    # data/apsaa/APSAA.zip -> data/features_apsaa.npz
  python3 training/prepare_data.py --selftest # held-out clips for the on-device test
  python3 training/prepare_data.py --prune    # delete raw audio after caching
"""
from __future__ import annotations
import csv
import glob
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ML = os.path.join(HERE, "..")
DATA = os.path.join(ML, "data")
sys.path.insert(0, HERE)
sys.path.insert(0, ML)

from audio_pipeline import SAMPLE_RATE, N_FRAMES, WINDOW_SAMPLES, HOP, LOG_FLOOR, logmel_frames  # noqa: E402
from esc50 import download as download_esc50  # noqa: E402

LABELS = ["snore", "cough", "speech", "other"]
STRIDE = 43  # frames between patches (~1 s)
# no single negative group may exceed this many patches in a split
GROUP_CAP = {"train": 450, "val": 150, "test": 200}

LIBRI_URL = "https://www.openslr.org/resources/31/dev-clean-2.tar.gz"
COUGH_URL = ("https://huggingface.co/datasets/szzs1693/edge-ai-cough-count/"
             "resolve/main/data/val-00000-of-00001.parquet")
FSD_BASE = "https://huggingface.co/datasets/Fhrozen/FSD50k/resolve/main"
LIBRI_DIR = os.path.join(DATA, "librispeech")
COUGH_PARQUET = os.path.join(DATA, "coughcount", "val.parquet")
FSD_DIR = os.path.join(DATA, "fsd50k")
OUT = os.path.join(DATA, "features.npz")
APSAA_ZIP = os.path.join(DATA, "apsaa", "APSAA.zip")
APSAA_URL = "https://zenodo.org/records/14096541/files/APSAA.zip?download=1"
APSAA_OUT = os.path.join(DATA, "features_apsaa.npz")

ESC_GROUPS = {
    "rain_water": ["rain", "water_drops", "pouring_water", "sea_waves", "toilet_flush"],
    "wind": ["wind"],
    "fan_appliance": ["vacuum_cleaner", "washing_machine"],
    "traffic": ["car_horn", "engine", "train", "siren", "airplane", "helicopter"],
    "rustle_movement": ["footsteps", "door_wood_creaks", "door_wood_knock", "keyboard_typing",
                        "mouse_click", "can_opening"],
    "breathing_nonspeech": ["breathing", "sneezing", "laughing", "crying_baby", "drinking_sipping",
                            "brushing_teeth"],
    "animals": ["dog", "cat", "rooster", "pig", "cow", "frog", "hen", "insects", "sheep", "crow",
                "chirping_birds"],
    "clock": ["clock_tick", "clock_alarm"],
}
ESC_GROUP_OF = {c: g for g, cs in ESC_GROUPS.items() for c in cs}

# FSD50K label -> group; a clip is taken only if it carries none of FSD_EXCLUDE
FSD_GROUPS = {
    "cough": ["Cough"],
    "rain_water": ["Rain", "Raindrop", "Water_tap_and_faucet", "Sink_(filling_or_washing)",
                   "Bathtub_(filling_or_washing)", "Toilet_flush"],
    "wind": ["Wind"],
    "fan_appliance": ["Mechanical_fan", "Microwave_oven"],
    "music": ["Music"],
    "traffic": ["Traffic_noise_and_roadway_noise", "Car_passing_by", "Motor_vehicle_(road)", "Engine",
                "Train"],
    "rustle_movement": ["Crumpling_and_crinkling", "Thump_and_thud", "Zipper_(clothing)",
                        "Walk_and_footsteps", "Door", "Sliding_door", "Typing"],
    "breathing_nonspeech": ["Breathing", "Sigh", "Gasp", "Chewing_and_mastication"],
    "animals": ["Purr", "Cat", "Dog"],
    "clock": ["Tick-tock", "Tick", "Clock"],
}
FSD_EXCLUDE = {"Speech", "Human_voice", "Singing", "Male_speech_and_man_speaking",
               "Female_speech_and_woman_speaking", "Child_speech_and_kid_speaking", "Conversation"}
FSD_LICENCES = {"http://creativecommons.org/publicdomain/zero/1.0/": "CC0",
                "http://creativecommons.org/licenses/by/3.0/": "CC-BY-3.0"}
FSD_PER_GROUP = {"train": 45, "val": 12, "test": 20}  # clips downloaded per group
FSD_MAX_BYTES = 1_500_000                            # skip long clips (~17 s at 44.1 kHz mono)


def _split_for(key: str) -> str:
    h = int(hashlib.md5(key.encode()).hexdigest(), 16) % 10
    return "train" if h < 6 else ("val" if h < 8 else "test")


def _resample(pcm: np.ndarray, sr: int) -> np.ndarray:
    if sr == SAMPLE_RATE:
        return pcm.astype(np.float32)
    # linear interpolation: images it creates sit above FMAX_HZ and are dropped
    n = int(len(pcm) * SAMPLE_RATE / sr)
    return np.interp(np.linspace(0, len(pcm) - 1, n), np.arange(len(pcm)), pcm).astype(np.float32)


def _read(path_or_bytes):
    import soundfile as sf
    pcm, sr = sf.read(path_or_bytes, dtype="float32")
    if pcm.ndim > 1:
        pcm = pcm.mean(axis=1)
    return _resample(pcm, sr)


def _pad(pcm: np.ndarray) -> np.ndarray:
    return pcm if len(pcm) >= WINDOW_SAMPLES else np.pad(pcm, (0, WINDOW_SAMPLES - len(pcm)))


def _rms_db(x: np.ndarray) -> float:
    return float(20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9))


def _patches(pcm: np.ndarray, active_only: bool, max_n: int | None = None, rng=None,
             stride: int = STRIDE):
    """Cut a clip into 86-frame patches. If active_only, drop patches >20 dB
    below the clip's loudest (silence inside a snore clip isn't a snore)."""
    pcm = _pad(pcm)
    lm = logmel_frames(pcm)
    starts = list(range(0, len(lm) - N_FRAMES + 1, stride))
    if active_only:
        lv = [_rms_db(pcm[s * HOP: s * HOP + WINDOW_SAMPLES]) for s in starts]
        top = max(lv)
        starts = [s for s, v in zip(starts, lv) if v > top - 20 and v > -60]
    if max_n and len(starts) > max_n:
        starts = sorted(rng.choice(starts, max_n, replace=False))
    return [lm[s:s + N_FRAMES] for s in starts]


# --------------------------------------------------------------------------- sources
# each yields (patch, label, split, source, clip_id, negative_group)

def esc50_items():
    meta = os.path.join(DATA, "ESC-50", "meta", "esc50.csv")
    fold_split = {1: "train", 2: "train", 3: "train", 4: "val", 5: "test"}
    for r in csv.DictReader(open(meta)):
        cat = r["category"]
        lab = {"snoring": "snore", "coughing": "cough"}.get(cat, "other")
        group = ESC_GROUP_OF.get(cat, "misc") if lab == "other" else ""
        pcm = _read(os.path.join(DATA, "ESC-50", "audio", r["filename"]))
        # many ESC clips are padded with silence; only positives need the
        # activity filter, and the scarce positives are cut ~0.5 s apart
        for p in _patches(pcm, active_only=lab != "other", stride=STRIDE if lab == "other" else STRIDE // 2):
            yield p, lab, fold_split[int(r["fold"])], "esc50", r["filename"], group


def fsd_items(rng):
    for row in csv.DictReader(open(os.path.join(FSD_DIR, "selected.csv"))):
        path = os.path.join(FSD_DIR, "clips", row["fname"] + ".wav")
        if not os.path.isfile(path):
            continue
        lab = "cough" if row["group"] == "cough" else "other"
        group = "" if lab == "cough" else row["group"]
        for p in _patches(_read(path), active_only=lab == "cough", max_n=3, rng=rng):
            yield p, lab, row["split"], "fsd50k", row["fname"], group


def libri_items(rng):
    for f in sorted(glob.glob(os.path.join(LIBRI_DIR, "**", "*.flac"), recursive=True)):
        speaker = os.path.basename(f).split("-")[0]
        for p in _patches(_read(f), active_only=True, max_n=2, rng=rng):
            yield p, "speech", _split_for("libri" + speaker), "librispeech", os.path.basename(f), ""


def cough_items(rng):
    import pyarrow.parquet as pq
    t = pq.read_table(COUGH_PARQUET, columns=["outward_facing_mic", "ground_truth", "subject_id",
                                              "noise", "sound", "has_ground_truth"]).to_pylist()
    half = WINDOW_SAMPLES // 2
    # this split has only two subjects: one trains, one is held out for test
    subjects = sorted({str(r["subject_id"]) for r in t})
    subject_split = {sid: ("train" if k % 2 == 0 else "test") for k, sid in enumerate(subjects)}
    for i, r in enumerate(t):
        # coughs only carry timestamps in cough trials; the laugh / deep-breathing /
        # throat-clearing trials have no coughs from the subject and are negatives
        if r["sound"] == "cough" and not r["has_ground_truth"]:
            continue
        pcm = _read(io.BytesIO(r["outward_facing_mic"]["bytes"]))
        split = subject_split[str(r["subject_id"])]
        gt = r["ground_truth"] or {}
        events = [(s, e) for s, e in zip(gt.get("start_times") or [], gt.get("end_times") or [])]
        if r["sound"] != "cough":
            events = []
        src = f"epfl_{r['subject_id']}_{i}"
        for s, e in events:  # one patch per cough, the cough placed at a random spot inside
            centre = int((s + e) / 2 * SAMPLE_RATE + rng.integers(-half // 2, half // 2))
            a = max(0, min(len(pcm) - WINDOW_SAMPLES, centre - half))
            seg = _pad(pcm[a:a + WINDOW_SAMPLES])
            yield logmel_frames(seg)[:N_FRAMES], "cough", split, "epfl", src, ""
        # negatives: patches clear of any labelled cough. Skip recordings whose
        # background noise is someone else coughing (those coughs are unlabelled).
        if "cough" in str(r["noise"]).lower():
            continue
        guard = 0.3 * SAMPLE_RATE
        spans = [(s * SAMPLE_RATE - guard, e * SAMPLE_RATE + guard) for s, e in events]
        kept = 0
        for a in range(0, len(pcm) - WINDOW_SAMPLES + 1, SAMPLE_RATE * 2):
            b = a + WINDOW_SAMPLES
            if any(a < se and b > ss for ss, se in spans):
                continue
            group = "breathing_nonspeech" if r["sound"] != "cough" else "misc"
            yield logmel_frames(pcm[a:b])[:N_FRAMES], "other", split, "epfl", src, group
            kept += 1
            if kept >= 6:
                break


def room_tone_items(rng, n_per_split={"train": 300, "val": 100, "test": 120}):
    """Near-silent bedrooms: coloured noise at -80..-45 dBFS, sometimes with mains hum."""
    t = np.arange(WINDOW_SAMPLES) / SAMPLE_RATE
    for split, n in n_per_split.items():
        for k in range(n):
            white = rng.standard_normal(WINDOW_SAMPLES)
            spec = np.fft.rfft(white)
            f = np.fft.rfftfreq(WINDOW_SAMPLES, 1 / SAMPLE_RATE)
            spec /= np.maximum(f, 20.0) ** rng.uniform(0.0, 1.0)   # white .. brown
            x = np.fft.irfft(spec, WINDOW_SAMPLES)
            if rng.random() < 0.3:
                mains = rng.choice([50.0, 60.0])
                x += rng.uniform(0.05, 0.5) * x.std() * np.sin(2 * np.pi * mains * t)
            x = x / (x.std() + 1e-9) * 10 ** (rng.uniform(-80, -45) / 20)
            yield logmel_frames(x.astype(np.float32))[:N_FRAMES], "other", split, "synthetic", f"room_{split}_{k}", "room_tone"


def tv_items(rng, X, y, split, group, n_per_split={"train": 300, "val": 100, "test": 120}):
    """TV in the room: a speech patch and a music patch from the same split,
    mixed at -10..+10 dB and coloured like a small speaker (bass and treble cut)."""
    lin = lambda p: np.exp(p.astype(np.float32)) - LOG_FLOOR  # noqa: E731
    shape = np.ones(X.shape[-1], np.float32)
    shape[:4], shape[-14:] = 0.2, 0.4
    for sp, n in n_per_split.items():
        speech = np.where((y == LABELS.index("speech")) & (split == sp))[0]
        music = np.where((group == "music") & (split == sp))[0]
        if len(speech) == 0 or len(music) == 0:
            continue
        for k in range(n):
            a, b = X[rng.choice(speech)], X[rng.choice(music)]
            mix = (lin(a) + lin(b) * 10 ** (rng.uniform(-10, 10) / 20)) * shape
            yield np.log(np.maximum(mix, 0) + LOG_FLOOR), "other", sp, "synthetic", f"tv_{sp}_{k}", "tv"


# --------------------------------------------------------------------------- APSAA

def _apsaa_split(subjects):
    """Patient-level split, deterministic: 20 train / 6 val / 6 test of 32."""
    order = np.random.default_rng(7).permutation(sorted(subjects))
    n_test = n_val = max(1, round(len(order) * 0.19))
    return {sid: ("test" if k < n_test else "val" if k < n_test + n_val else "train")
            for k, sid in enumerate(order)}


def apsaa_items(rng, max_snore=250, neg_blocks=50):
    """APSAA overnight hospital recordings (4 kHz mono, synchronised with a
    polygraph). Snore: 1-s-stride windows inside the technicians' manual
    "Snore" annotations. Other: blocks of 5 consecutive windows >= 15 s from
    any snore annotation where the polygraph snore channel (Snore_EG, 10 Hz)
    has no snore-like spike (peak under its 90th percentile away from
    annotated snores), so unannotated snoring isn't used as a negative. Windows are resampled 4 kHz -> 44.1 kHz with a polyphase filter
    (nothing above 2 kHz, unlike the other sources; training band-limits a share
    of the other sources to match). Research / non-commercial use only."""
    import zipfile
    from scipy.signal import resample_poly
    z = zipfile.ZipFile(APSAA_ZIP)
    subjects = sorted({n.split("/")[0] for n in z.namelist() if n.endswith(".wav")})
    split = _apsaa_split(subjects)
    src_sr, win_s = 4000, WINDOW_SAMPLES / SAMPLE_RATE
    for sid in subjects:
        import soundfile as sf
        with z.open(f"{sid}/{sid}.wav") as f:
            pcm, sr = sf.read(io.BytesIO(f.read()), dtype="float32")
        assert sr == src_sr, (sid, sr)
        dur = len(pcm) / sr
        ann = list(csv.DictReader(io.TextIOWrapper(z.open(f"{sid}/{sid}_Annotations.csv"))))
        def secs(t):
            h, m, s_ = (float(x) for x in t.split(":"))
            return h * 3600 + m * 60 + s_
        snores = [(secs(a["Start_Time"]), secs(a["Start_Time"]) + float(a["Duration"]))
                  for a in ann if a["Event_Name"].strip().lower() == "snore"]
        eg = np.array([float(l) for l in io.TextIOWrapper(z.open(f"{sid}/{sid}_Snore_EG.csv")).read().split()[1:]])
        # the snore channel's level away from annotated snores (>= 15 s): a window
        # whose peak stays under its 90th percentile has no snore-like pressure spike
        far = np.ones(len(eg), bool)
        for s0, e0 in snores:
            far[max(0, int((s0 - 15) * 10)):int((e0 + 15) * 10)] = False
        eg_quiet = np.percentile(eg[far], 90) if far.any() else np.percentile(eg, 50)

        def window(t0):
            a = int(t0 * sr)
            seg = pcm[a:a + int(np.ceil(win_s * sr)) + 8]
            up = resample_poly(seg, 441, 40).astype(np.float32)
            return logmel_frames(_pad(up))[:N_FRAMES]

        starts = [t for s0, e0 in snores for t in
                  (np.arange(s0, e0 - win_s + 1e-6, 1.0) if e0 - s0 >= win_s else [max(0.0, (s0 + e0 - win_s) / 2)])]
        if len(starts) > max_snore:
            starts = sorted(rng.choice(starts, max_snore, replace=False))
        for t in starts:
            if t + win_s < dur:
                yield window(t), "snore", split[sid], "apsaa", f"{sid}_{int(t) // 5}", ""

        def clear(t0, t1):
            if any(t0 - 15 < e0 and t1 + 15 > s0 for s0, e0 in snores):
                return False
            seg = eg[int(t0 * 10):int(t1 * 10) + 1]
            return len(seg) > 0 and seg.max() <= eg_quiet
        cands = [t for t in np.arange(30.0, dur - 10, 5.0) if clear(t, t + 4 + win_s)]
        for t in sorted(rng.choice(cands, min(neg_blocks, len(cands)), replace=False)):
            for k in range(5):
                yield window(t + k), "other", split[sid], "apsaa", f"{sid}_neg{int(t)}", "apsaa_overnight"
        print(f"  APSAA {sid} ({split[sid]}): {len(snores)} snore events, {len(starts)} snore windows, "
              f"{min(neg_blocks, len(cands))} quiet blocks", flush=True)


def build_apsaa():
    rng = np.random.default_rng(3)
    X, y, split, source, clip, group = [], [], [], [], [], []
    for p, lab, sp, src, cid, grp in apsaa_items(rng):
        X.append(p.astype(np.float16)); y.append(LABELS.index(lab)); split.append(sp)
        source.append(src); clip.append(cid); group.append(grp)
    X, y, split = np.stack(X)[:, None], np.array(y), np.array(split)
    np.savez_compressed(APSAA_OUT, X=X, y=y, split=split, source=np.array(source), group=np.array(clip),
                        neg_group=np.array(group), labels=np.array(LABELS))
    print(f"wrote {APSAA_OUT}: {X.shape}")
    for sp in ("train", "val", "test"):
        m = split == sp
        print(f"  {sp:5s}", {LABELS[c]: int(((y == c) & m).sum()) for c in range(len(LABELS))})


# --------------------------------------------------------------------------- download

def _fsd_select(rng):
    """Pick FSD50K clips per group: individually CC0 / CC BY 3.0 only, no
    speech labels, single-group, deterministic."""
    meta = os.path.join(FSD_DIR, "meta")
    info = {}
    for part in ("dev", "eval"):
        info.update(json.load(open(os.path.join(meta, f"{part}_clips_info_FSD50K.json"))))
    rows = []
    for part in ("dev", "eval"):
        for r in csv.DictReader(open(os.path.join(meta, f"{part}.csv"))):
            labs = set(r["labels"].split(","))
            lic = FSD_LICENCES.get(info.get(r["fname"], {}).get("license"))
            if lic is None or labs & FSD_EXCLUDE:
                continue
            groups = [g for g, ls in FSD_GROUPS.items() if labs & set(ls)]
            if len(groups) != 1:
                continue
            split = {"train": "train", "val": "val"}[r["split"]] if part == "dev" else "test"
            rows.append(dict(fname=r["fname"], group=groups[0], split=split, licence=lic,
                             uploader=info[r["fname"]].get("uploader", ""), labels=r["labels"]))
    chosen = []
    for g in FSD_GROUPS:
        for sp, n in FSD_PER_GROUP.items():
            pool = [r for r in rows if r["group"] == g and r["split"] == sp]
            idx = rng.permutation(len(pool))[: n * 2]   # spares for over-long clips
            chosen += [pool[i] for i in idx]
    return chosen


def download_fsd(rng):
    meta = os.path.join(FSD_DIR, "meta")
    os.makedirs(meta, exist_ok=True)
    for f in ("labels/dev.csv", "labels/eval.csv", "labels/vocabulary.csv",
              "metadata/dev_clips_info_FSD50K.json", "metadata/eval_clips_info_FSD50K.json"):
        dst = os.path.join(meta, os.path.basename(f))
        if not os.path.isfile(dst):
            urllib.request.urlretrieve(f"{FSD_BASE}/{f}", dst)
    clips = os.path.join(FSD_DIR, "clips")
    os.makedirs(clips, exist_ok=True)

    def fetch(r):
        part = "eval" if r["split"] == "test" else "dev"
        dst = os.path.join(clips, r["fname"] + ".wav")
        if os.path.isfile(dst):
            return True
        # curl's --max-filesize skips long clips without downloading them
        rc = subprocess.run(["curl", "-sfL", "--max-filesize", str(FSD_MAX_BYTES), "-o", dst,
                             f"{FSD_BASE}/clips/{part}/{r['fname']}.wav"]).returncode
        if rc != 0 and os.path.exists(dst):
            os.remove(dst)
        return rc == 0

    def bucket(rows):  # walk one (group, split) candidate list until it has enough clips
        got = []
        for r in rows:
            if len(got) >= FSD_PER_GROUP[r["split"]]:
                break
            if fetch(r):
                got.append(r)
        return got

    buckets = {}
    for r in _fsd_select(rng):
        buckets.setdefault((r["group"], r["split"]), []).append(r)
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(8) as ex:
        results = dict(zip(buckets, ex.map(bucket, buckets.values())))
    picked = [r for k in buckets for r in results[k]]
    need = {k: len(v) for k, v in results.items()}
    with open(os.path.join(FSD_DIR, "selected.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(picked[0].keys()))
        w.writeheader()
        w.writerows(picked)
    print(f"FSD50K: {len(picked)} clips", {k: v for k, v in sorted(need.items())})


def download():
    download_esc50()
    os.makedirs(LIBRI_DIR, exist_ok=True)
    if not glob.glob(os.path.join(LIBRI_DIR, "**", "*.flac"), recursive=True):
        tgz = os.path.join(LIBRI_DIR, "dev-clean-2.tar.gz")
        if not os.path.isfile(tgz):
            print("downloading Mini LibriSpeech dev-clean-2 (126 MB)")
            urllib.request.urlretrieve(LIBRI_URL, tgz)
        with tarfile.open(tgz) as tf:
            tf.extractall(LIBRI_DIR, filter="data")
        os.remove(tgz)
    if not os.path.isfile(COUGH_PARQUET):
        os.makedirs(os.path.dirname(COUGH_PARQUET), exist_ok=True)
        print("downloading EPFL edge-AI cough count, val split (118 MB)")
        urllib.request.urlretrieve(COUGH_URL, COUGH_PARQUET)
    download_fsd(np.random.default_rng(1))


# --------------------------------------------------------------------------- build

def build():
    rng = np.random.default_rng(0)
    X, y, split, source, clip, group = [], [], [], [], [], []

    def add(gen):
        for p, lab, sp, src, cid, grp in gen:
            X.append(p.astype(np.float16))
            y.append(LABELS.index(lab))
            split.append(sp)
            source.append(src)
            clip.append(cid)
            group.append(grp)

    for gen in (esc50_items(), fsd_items(rng), libri_items(rng), cough_items(rng), room_tone_items(rng)):
        add(gen)
    add(list(tv_items(rng, np.stack(X), np.array(y), np.array(split), np.array(group))))

    X, y, split, group = np.stack(X)[:, None], np.array(y), np.array(split), np.array(group)
    source, clip = np.array(source), np.array(clip)
    # cap every negative group per split so no single source dominates "other"
    keep = np.ones(len(y), bool)
    for sp, cap in GROUP_CAP.items():
        for g in set(group[group != ""]):
            idx = np.where((group == g) & (split == sp))[0]
            if len(idx) > cap:
                keep[rng.choice(idx, len(idx) - cap, replace=False)] = False
    X, y, split, group, source, clip = X[keep], y[keep], split[keep], group[keep], source[keep], clip[keep]

    np.savez_compressed(OUT, X=X, y=y, split=split, source=source, group=clip, neg_group=group,
                        labels=np.array(LABELS))
    print(f"wrote {OUT}: {X.shape}")
    for sp in ("train", "val", "test"):
        m = split == sp
        print(f"  {sp:5s}", {LABELS[c]: int(((y == c) & m).sum()) for c in range(len(LABELS))})
    print("  negative groups (train/val/test):")
    for g in sorted(set(group[group != ""])):
        print(f"    {g:20s}", [int(((group == g) & (split == sp)).sum()) for sp in ("train", "val", "test")])


def selftest_clips():
    """Write two held-out test recordings for the on-device integration test to
    data/selftest/: ~40 s of ESC-50 fold-5 snoring, and ~60 s of held-out
    negatives (one clip per group, ESC-50 fold 5 / FSD50K eval). Copy them into
    flutter_app/assets/models/ (gitignored) only while running that test, so
    they never ship in a normal build and are never committed."""
    import soundfile as sf
    out = os.path.join(DATA, "selftest")
    os.makedirs(out, exist_ok=True)
    meta = list(csv.DictReader(open(os.path.join(DATA, "ESC-50", "meta", "esc50.csv"))))
    snore = [r["filename"] for r in meta if r["category"] == "snoring" and r["fold"] == "5"]
    pcm = np.concatenate([_read(os.path.join(DATA, "ESC-50", "audio", f)) for f in snore])
    sf.write(os.path.join(out, "selftest_snore.wav"), pcm, SAMPLE_RATE, subtype="PCM_16")
    negs, seen = [], set()
    for r in meta:
        g = ESC_GROUP_OF.get(r["category"])
        if r["fold"] == "5" and g and g not in seen:
            seen.add(g)
            negs.append(_read(os.path.join(DATA, "ESC-50", "audio", r["filename"])))
    for row in csv.DictReader(open(os.path.join(FSD_DIR, "selected.csv"))):
        if row["split"] == "test" and row["group"] in ("music", "fan_appliance", "breathing_nonspeech", "traffic") \
                and ("fsd", row["group"]) not in seen:
            seen.add(("fsd", row["group"]))
            negs.append(_read(os.path.join(FSD_DIR, "clips", row["fname"] + ".wav"))[: 5 * SAMPLE_RATE])
    sf.write(os.path.join(out, "selftest_other.wav"), np.concatenate(negs), SAMPLE_RATE, subtype="PCM_16")
    print(f"wrote selftest clips: snore {len(pcm) / SAMPLE_RATE:.0f} s, other "
          f"{sum(map(len, negs)) / SAMPLE_RATE:.0f} s")
    selftest_apsaa()


def selftest_apsaa():
    """60 s of annotated snoring and 60 s of quiet from a held-out APSAA patient
    (research-only data; local test builds only, never committed)."""
    import soundfile as sf
    out = os.path.join(DATA, "selftest")
    os.makedirs(out, exist_ok=True)
    if os.path.isfile(APSAA_ZIP):
        import zipfile
        from scipy.signal import resample_poly
        z = zipfile.ZipFile(APSAA_ZIP)
        subjects = sorted({n.split("/")[0] for n in z.namelist() if n.endswith(".wav")})
        sid = sorted(s_ for s_, sp in _apsaa_split(subjects).items() if sp == "test")[0]
        rec, sr = sf.read(io.BytesIO(z.read(f"{sid}/{sid}.wav")), dtype="float32")
        ann = list(csv.DictReader(io.TextIOWrapper(z.open(f"{sid}/{sid}_Annotations.csv"))))
        secs = lambda t: sum(float(x) * m for x, m in zip(t.split(":"), (3600, 60, 1)))  # noqa: E731
        sn = sorted((secs(a["Start_Time"]), secs(a["Start_Time"]) + float(a["Duration"]))
                    for a in ann if a["Event_Name"].strip().lower() == "snore")
        cover = lambda t: sum(max(0.0, min(e, t + 60) - max(s_, t)) for s_, e in sn)  # noqa: E731
        t_sn = max(np.arange(0, len(rec) / sr - 60, 5.0), key=cover)
        t_q = next(t for t in np.arange(600, len(rec) / sr - 60, 30.0)
                   if all(e < t - 30 or s_ > t + 90 for s_, e in sn))
        for name, t in (("selftest_apsaa_snore.wav", t_sn), ("selftest_apsaa_quiet.wav", t_q)):
            seg = rec[int(t * sr):int((t + 60) * sr)]
            sf.write(os.path.join(out, name), resample_poly(seg, 441, 40).astype(np.float32), SAMPLE_RATE,
                     subtype="PCM_16")
        print(f"wrote APSAA selftest clips from held-out patient {sid}: snore stretch at {t_sn:.0f} s "
              f"({cover(t_sn):.0f} s annotated), quiet stretch at {t_q:.0f} s")


def prune():
    """Delete raw audio once features.npz exists (keeps licences + metadata)."""
    assert os.path.isfile(OUT), "build features first"
    shutil.rmtree(os.path.join(DATA, "ESC-50", "audio"), ignore_errors=True)
    shutil.rmtree(os.path.join(FSD_DIR, "clips"), ignore_errors=True)
    for d in glob.glob(os.path.join(LIBRI_DIR, "*")):
        if os.path.isdir(d):
            shutil.rmtree(d)
    if os.path.isfile(COUGH_PARQUET):
        os.remove(COUGH_PARQUET)
    print("raw audio removed; features cache kept")


if __name__ == "__main__":
    if "--download" in sys.argv:
        download()
    elif "--apsaa" in sys.argv:
        build_apsaa()
    elif "--selftest-apsaa" in sys.argv:
        selftest_apsaa()
    elif "--selftest" in sys.argv:
        selftest_clips()
    elif "--prune" in sys.argv:
        prune()
    else:
        build()
