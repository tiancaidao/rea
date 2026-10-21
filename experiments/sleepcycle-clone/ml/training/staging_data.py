"""
Build the sleep-staging training set from open accelerometer + PSG data.

Input to the model is motion only (the phone has no heart rate), turned into
the SAME per-30-s-epoch movement number the app computes from the phone
accelerometer (flutter_app/lib/sensing/live_tracker.dart):

    mag    = |acceleration| in g, sampled at 50 Hz
    energy = sum over the epoch of |mag[k] - mag[k-1]|
    spikes = number of samples with |mag[k] - mag[k-1]| > 0.03 g
    raw    = spikes + energy

Domain gap: the training data is a wrist sensor, the app a phone lying on the
mattress, which sees attenuated, smoothed motion. Each night is therefore also
rendered as phone-like variants (motion attenuated 2-20x around its local mean,
optionally smoothed, plus phone-grade sensor noise) and training draws
variants at random.

Sources (licences verified 2026-10-22, see DATASETS.md):
  Walch et al. 2019, PhysioNet sleep-accel 1.0.0   ODC Attribution 1.0   31 subjects
  Newcastle PSG + GENEActiv wrist, van Hees 2018, Zenodo 1160410  CC BY 4.0  28 subjects

Split by subject within each source: 60 / 20 / 20, deterministic.

  python3 training/staging_data.py            # data/staging/walch/{motion,labels}/ -> data/staging_features.npz
  (download: WALCH_URL/labels/<id>_labeled_sleep.txt and WALCH_URL/motion/<id>_acceleration.txt)
"""
from __future__ import annotations
import os
import sys

import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
WALCH_DIR = os.path.join(DATA, "staging", "walch")      # motion/ and labels/ from PhysioNet
WALCH_URL = "https://physionet-open.s3.amazonaws.com/sleep-accel/1.0.0"  # PhysioNet's open-data mirror
OUT = os.path.join(DATA, "staging_features.npz")

FS = 50          # the app samples the accelerometer every 20 ms
EPOCH = 30
SPIKE_G = 0.03   # live_tracker.dart: if (d > 0.03) _spikes++
STAGES = ["wake", "light", "deep", "rem"]
PSG_TO_STAGE = {0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 3}   # AASM N1/N2 -> light, N3(/N4) -> deep
# (attenuation, smoothing samples, noise g): variant 0 is the sensor as recorded
VARIANTS = [(1.0, 1, 0.0), (0.5, 1, 0.002), (0.25, 1, 0.002), (0.1, 1, 0.002), (0.05, 1, 0.002),
            (0.25, 5, 0.002), (0.1, 5, 0.002), (0.05, 10, 0.002)]


def epoch_raw(mag: np.ndarray, n_epochs: int) -> np.ndarray:
    """The app's per-epoch movement number from a 50 Hz magnitude signal."""
    d = np.abs(np.diff(mag, prepend=mag[:1]))
    per = FS * EPOCH
    d = d[: n_epochs * per].reshape(n_epochs, per)
    return d.sum(1) + (d > SPIKE_G).sum(1)


def phone_like(mag: np.ndarray, att: float, smooth: int, noise: float, rng) -> np.ndarray:
    if att == 1.0 and smooth == 1 and noise == 0.0:
        return mag
    k = FS * 5
    local = np.convolve(mag, np.ones(k) / k, mode="same")       # slow posture / gravity part
    m = local + att * (mag - local)
    if smooth > 1:
        m = np.convolve(m, np.ones(smooth) / smooth, mode="same")
    return m + rng.normal(0, noise, len(m)) if noise else m


def _split(subjects):
    order = np.random.default_rng(11).permutation(sorted(subjects))
    n = len(order)
    n_test, n_val = round(n * 0.2), round(n * 0.2)
    return {s: ("test" if k < n_test else "val" if k < n_test + n_val else "train") for k, s in enumerate(order)}


def walch_nights():
    for lf in sorted(os.listdir(os.path.join(WALCH_DIR, "labels"))):
        sid = lf.split("_")[0]
        mf = os.path.join(WALCH_DIR, "motion", f"{sid}_acceleration.txt")
        if not os.path.isfile(mf):
            continue
        yield sid, np.loadtxt(os.path.join(WALCH_DIR, "labels", lf)), np.loadtxt(mf)


NEWCASTLE_ZIP = os.path.join(DATA, "staging", "newcastle", "psgnewcastle2015.zip")
NC_STAGE = {"W": 0, "N1": 1, "N2": 1, "N3": 2, "R": 3}


def read_geneactiv(raw: bytes):
    """GENEActiv .bin (text pages of hex samples) -> (t seconds since epoch, x, y, z in g)."""
    from datetime import datetime
    txt = raw.decode("latin1").replace("\r", "")
    head, _, body = txt.partition("Recorded Data")
    cal = {}
    for line in head.split("\n"):
        k, _, v = line.partition(":")
        if k.strip() in ("x gain", "x offset", "y gain", "y offset", "z gain", "z offset"):
            cal[k.strip()] = float(v)
    ts, xyz = [], []
    for page in ("Recorded Data" + body).split("Recorded Data")[1:]:
        meta, hexline = {}, ""
        for line in page.split("\n"):
            k, sep, v = line.partition(":")
            if sep and not k.startswith(("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F")):
                meta[k.strip()] = v.strip()
            elif len(line.strip()) >= 12:
                hexline = line.strip()
        if not hexline:
            continue
        fs = float(meta.get("Measurement Frequency", 85.7))
        t0 = datetime.strptime(meta["Page Time"], "%Y-%m-%d %H:%M:%S:%f").timestamp()
        b = np.frombuffer(bytes.fromhex(hexline), dtype=np.uint8).reshape(-1, 6).astype(np.int64)
        v = (b[:, 0] << 40) | (b[:, 1] << 32) | (b[:, 2] << 24) | (b[:, 3] << 16) | (b[:, 4] << 8) | b[:, 5]
        comp = np.stack([(v >> 36) & 0xFFF, (v >> 24) & 0xFFF, (v >> 12) & 0xFFF], 1)
        comp = np.where(comp >= 2048, comp - 4096, comp)
        ts.append(t0 + np.arange(len(v)) / fs)
        xyz.append(comp)
    xyz = np.concatenate(xyz).astype(np.float64)
    for i, a in enumerate("xyz"):
        xyz[:, i] = (xyz[:, i] * 100 - cal[f"{a} offset"]) / cal[f"{a} gain"]
    return np.concatenate(ts), xyz


def newcastle_nights():
    """Newcastle PSG + GENEActiv (van Hees 2018, CC BY 4.0): left wrist, 30-s PSG
    stages against clock time. Yields (subject, labels[[t, stage]], acc[[t, x, y, z]])
    with times in seconds from PSG start, the same layout as walch_nights()."""
    from datetime import datetime, timedelta
    z = zipfile.ZipFile(NEWCASTLE_ZIP)
    for psg in sorted(n for n in z.namelist() if n.endswith("_psg.txt")):
        num = os.path.basename(psg)[len("mecsleep"):].split("_")[0]
        accs = [n for n in z.namelist() if f"/MECSLEEP{num}_left wrist" in n] or \
               [n for n in z.namelist() if f"/MECSLEEP{num}_right wrist" in n]
        if not accs:
            continue
        lines = z.read(psg).decode("latin1").replace("\r", "").split("\n")
        date = next(l.split("\t")[-1].strip() for l in lines if l.startswith("Recording Date"))
        day = datetime.strptime(date, "%d/%m/%Y")
        hdr = next(i for i, l in enumerate(lines) if l.startswith("Sleep Stage"))
        rows, prev = [], None
        for l in lines[hdr + 1:]:
            f = l.split("\t")
            clock = next((x for x in f if __import__("re").fullmatch(r"\d{1,2}:\d{2}:\d{2}", x.strip())), None)
            if len(f) < 3 or clock is None or (f[0] not in NC_STAGE and f[0] != "Unscored"):
                continue
            hh, mm, ss = (int(x) for x in clock.strip().split(":"))
            t = day.replace(hour=hh, minute=mm, second=ss)
            if prev is not None and t < prev - timedelta(hours=1):
                day += timedelta(days=1)
                t += timedelta(days=1)
            prev = t
            rows.append((t.timestamp(), NC_STAGE_PSG.get(f[0], -1)))
        t0 = rows[0][0]
        lab = np.array([(t - t0, s) for t, s in rows])
        ts, xyz = read_geneactiv(z.read(accs[0]))
        acc = np.column_stack([ts - t0, xyz])
        yield f"ncl{num}", lab, acc


# Newcastle labels in the Walch integer coding, so build() maps both the same way
NC_STAGE_PSG = {"W": 0, "N1": 1, "N2": 2, "N3": 3, "R": 5}


def build():
    rng = np.random.default_rng(0)
    rows = []
    nights = list(walch_nights())
    if os.path.isfile(NEWCASTLE_ZIP):
        nights = __import__("itertools").chain(nights, newcastle_nights())
    source_of = {}
    for sid, lab, acc in nights:
        source_of[sid] = "newcastle" if sid.startswith("ncl") else "walch"
        lab = lab[lab[:, 1] >= 0]
        if source_of[sid] == "newcastle":
            # the clinic PSG runs ~12 h incl. lights-on wake; the app tracks in bed:
            # keep 30 min before sleep onset to 30 min after the final awakening
            asleep = np.where(lab[:, 1] > 0)[0]
            lab = lab[max(0, asleep[0] - 60): asleep[-1] + 61]
        t0, n = lab[0, 0], len(lab)
        stage = np.array([PSG_TO_STAGE.get(int(s), -1) for s in lab[:, 1]])
        a = acc[(acc[:, 0] >= t0) & (acc[:, 0] < t0 + n * EPOCH)]
        a = a[np.argsort(a[:, 0])]
        if len(a) < FS * 3600:
            print(f"  {sid}: skipped, accelerometer barely overlaps the PSG ({len(a) / FS / 60:.0f} min)")
            continue
        grid = t0 + np.arange(n * EPOCH * FS) / FS
        mag = np.sqrt((a[:, 1:4] ** 2).sum(1))
        magu = np.interp(grid, a[:, 0], mag)
        # epochs where the recording has a gap > 2 s carry no motion information
        gap = np.zeros(len(grid), bool)
        big = np.where(np.diff(a[:, 0]) > 2.0)[0]
        for g in big:
            gap[(grid > a[g, 0]) & (grid < a[g + 1, 0])] = True
        gap |= (grid < a[0, 0]) | (grid > a[-1, 0])
        valid = ~gap.reshape(n, -1).any(1)
        raws = np.stack([epoch_raw(phone_like(magu, at, sm, no, rng), n) for at, sm, no in VARIANTS])
        if valid.mean() < 0.5:
            print(f"  {sid}: skipped, motion recorded for only {valid.mean():.0%} of the night")
            continue
        rows.append((sid, raws.astype(np.float32), stage, valid))
        print(f"  {sid}: {n} epochs ({n / 120:.1f} h), {valid.mean():.0%} with motion, stages "
              f"{np.bincount(stage[stage >= 0], minlength=4).tolist()}", flush=True)
    # split each source by subject on its own, so both are in train / val / test
    split = {}
    for src in ("walch", "newcastle"):
        split.update(_split([r[0] for r in rows if source_of[r[0]] == src]))

    def obj(k):  # ragged per-night arrays
        a = np.empty(len(rows), dtype=object)
        for i, r in enumerate(rows):
            a[i] = r[k]
        return a
    np.savez_compressed(OUT, subjects=np.array([r[0] for r in rows]), split=np.array([split[r[0]] for r in rows]),
                        raw=obj(1), stage=obj(2), valid=obj(3), variants=np.array(VARIANTS),
                        stages=np.array(STAGES), source=np.array([source_of[r[0]] for r in rows]))
    print(f"wrote {OUT}: {len(rows)} nights", {s: sum(1 for r in rows if split[r[0]] == s) for s in ("train", "val", "test")})


if __name__ == "__main__":
    build()
