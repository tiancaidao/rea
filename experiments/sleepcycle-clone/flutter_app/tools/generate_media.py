#!/usr/bin/env python3
"""Synthesise the app's own audio: alarm melodies and sleep-aid ambiences.

Everything is generated from oscillators and filtered noise (numpy only), so
the clip set is ours to ship: a clean checkout has real alarm and ambience
audio without the APK placeholders. Output: assets/audio/own/*.mp3 (needs
ffmpeg with libmp3lame on PATH).

    python3 tools/generate_media.py            # writes assets/audio/own/
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio', 'own')
rng = np.random.default_rng(7)


# ── building blocks ─────────────────────────────────────────────────────────
def lowpass(x, cutoff):
    """One-pole low-pass, run forwards and backwards (zero phase)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    def run(v):
        y = np.empty_like(v)
        acc = 0.0
        for i, s in enumerate(v):
            acc = (1 - a) * s + a * acc
            y[i] = acc
        return y
    return run(run(x)[::-1])[::-1]


def fast_lowpass(x, cutoff):
    """Same filter via FFT (much faster for long noise beds)."""
    f = np.fft.rfftfreq(len(x), 1 / SR)
    h = 1 / (1 + (f / cutoff) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * h, len(x))


def bandpass(x, lo, hi):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    h = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * h, len(x))


def white(n):
    return rng.standard_normal(n)


def pink(n):
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(white(n)) / np.sqrt(np.maximum(f, 20))
    return np.fft.irfft(spec, n)


def brown(n):
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = np.fft.rfft(white(n)) / np.maximum(f, 20)
    return np.fft.irfft(spec, n)


def norm(x, peak=0.8):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def loopable(x, fade=1.5):
    """Crossfade the tail into the head so the clip loops without a click."""
    k = int(fade * SR)
    head, tail = x[:k], x[-k:]
    w = np.linspace(0, 1, k)
    x = x[:-k].copy()
    x[:k] = head * w + tail * (1 - w)
    return x


def env_adsr(n, a=0.01, d=0.3, s=0.4, r=0.8):
    t = np.arange(n) / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / d))
    rel = np.clip((n / SR - t) / r, 0, 1)
    return e * rel


def bell(freq, dur, bright=1.0):
    """Soft FM bell / kalimba tone."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    mod = bright * 2.0 * np.exp(-t * 3) * np.sin(2 * np.pi * freq * 3.5 * t)
    tone = np.sin(2 * np.pi * freq * t + mod) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    return tone * env_adsr(n, a=0.005, d=0.5, s=0.0, r=0.3) * np.exp(-t * 1.2)


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = sum(np.sin(2 * np.pi * f * t + 0.3 * np.sin(2 * np.pi * 0.2 * t)) for f in freqs)
    return x * env_adsr(n, a=dur * 0.4, d=1, s=1, r=dur * 0.4)


def note(name):
    names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    octave = int(name[-1])
    semis = names.index(name[:-1]) + 12 * (octave - 4) - 9
    return 440.0 * 2 ** (semis / 12)


def melody(seq, beat, total, bright=1.0, pad_chords=None, swell=True):
    """Bell melody over optional pads; volume swells up like a gentle alarm."""
    n = int(total * SR)
    x = np.zeros(n)
    t = 0.0
    while t < total - 2:
        for name, beats in seq:
            if t >= total - 2:
                break
            if name:
                b = bell(note(name), min(3.0, beats * beat + 1.5), bright)
                i = int(t * SR)
                x[i:i + len(b)] += b[:max(0, n - i)]
            t += beats * beat
    if pad_chords:
        seg = total / len(pad_chords)
        for k, chord in enumerate(pad_chords):
            p = 0.18 * pad([note(c) for c in chord], seg + 1)
            i = int(k * seg * SR)
            x[i:i + len(p)] += p[:max(0, n - i)]
    if swell:
        x *= np.linspace(0.35, 1.0, n) ** 0.7
    return x


# ── alarm sounds (names match AlarmSoundPage.free) ──────────────────────────
def alarms():
    return {
        'alarm_soft_breeze': melody([('E5', 1), ('G5', 1), ('B5', 1), ('E6', 2), ('B5', 1), ('G5', 2)], 0.42, 30,
                                    pad_chords=[('E3', 'B3', 'G4'), ('C3', 'G3', 'E4')] * 3)
                             + 0.05 * fast_lowpass(pink(30 * SR), 900),
        'alarm_forest_clearing': melody([('D5', 1), ('F#5', 1), ('A5', 2), (None, 1), ('A5', 1), ('B5', 1), ('D6', 3)],
                                        0.36, 30, bright=0.6) + birds(30) * 0.35,
        'alarm_morning_haze': melody([('C5', 2), ('E5', 2), ('G5', 2), ('B5', 2), ('A5', 4)], 0.5, 30, bright=0.4,
                                     pad_chords=[('C3', 'G3', 'E4'), ('A2', 'E3', 'C4'), ('F2', 'C3', 'A3')] * 2),
        'alarm_first_light': melody([('G4', 1), ('C5', 1), ('E5', 1), ('G5', 1), ('C6', 2), ('G5', 2)], 0.3, 30),
        'alarm_dewdrops': melody([('A5', 0.5), ('E6', 0.5), ('C#6', 1), (None, 0.5), ('B5', 0.5), ('E6', 1), (None, 2)],
                                 0.4, 30, bright=1.6),
        'alarm_classical_morning': melody([('G4', 1), ('B4', 1), ('D5', 1), ('G5', 1), ('F#5', 1), ('D5', 1), ('E5', 1),
                                           ('C5', 1), ('A4', 1), ('C5', 1), ('B4', 2)], 0.33, 30, bright=0.8,
                                          pad_chords=[('G2', 'D3', 'B3'), ('C3', 'G3', 'E4'), ('D3', 'A3', 'F#4')] * 2),
        'alarm_rain_and_wind': 0.7 * rain(30) + 0.5 * melody([('D5', 2), ('A5', 2), ('F5', 4)], 0.6, 30, bright=0.3),
        'alarm_far_memories': melody([('A4', 1.5), ('C5', 0.5), ('E5', 1), ('D5', 1), ('C5', 1), ('B4', 1), ('A4', 2)],
                                     0.45, 30, bright=0.5, pad_chords=[('A2', 'E3', 'C4'), ('F2', 'C3', 'A3')] * 3),
    }


# ── ambiences (loop seamlessly) ──────────────────────────────────────────────
def rain(dur):
    n = int(dur * SR)
    bed = fast_lowpass(pink(n), 3500) * 0.6
    drops = np.zeros(n)
    for i in rng.integers(0, n - 400, int(dur * 120)):
        k = np.arange(300)
        drops[i:i + 300] += rng.uniform(0.2, 1) * np.exp(-k / 40) * np.sin(2 * np.pi * rng.uniform(1500, 5000) * k / SR)
    return norm(bed + 0.25 * drops, 0.6)


def wind(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 9.0) * np.sin(2 * np.pi * t / 23.0 + 1)
    return norm(bandpass(white(n), 150, 900) * gust, 0.6)


def ocean(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    swell = np.clip(np.sin(2 * np.pi * t / 7.5), 0, 1) ** 2 + 0.15
    return norm(fast_lowpass(pink(n), 1200) * swell + 0.3 * brown(n) / np.std(brown(n)) * 0.2, 0.6)


def fire(dur):
    n = int(dur * SR)
    bed = fast_lowpass(brown(n), 500)
    bed = bed / np.std(bed) * 0.3
    crack = np.zeros(n)
    for i in rng.integers(0, n - 200, int(dur * 25)):
        k = np.arange(150)
        crack[i:i + 150] += rng.uniform(0.3, 1) * np.exp(-k / 15) * white(150)
    return norm(bed + bandpass(crack, 800, 6000), 0.6)


def crickets(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    chirp = np.sin(2 * np.pi * 4300 * t) * (np.sin(2 * np.pi * 28 * t) > 0.3) * (np.sin(2 * np.pi * 0.9 * t) > 0)
    bed = fast_lowpass(pink(n), 800)
    return norm(0.15 * chirp + bed / np.std(bed) * 0.25, 0.5)


def stream(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    burble = bandpass(white(n), 300, 2500) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.37 * t) * np.sin(2 * np.pi * 1.3 * t))
    return norm(burble, 0.55)


def birds(dur):
    n = int(dur * SR)
    x = np.zeros(n)
    for start in rng.uniform(0, dur - 1, int(dur / 2.5)):
        k = int(0.18 * SR)
        tt = np.arange(k) / SR
        f = rng.uniform(2500, 4200) + 1200 * np.sin(2 * np.pi * rng.uniform(8, 18) * tt)
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / tt[-1])
        i = int(start * SR)
        x[i:i + k] += s
    return x


def ambiences(dur=36):
    return {
        'amb_rain': rain(dur),
        'amb_wind': wind(dur),
        'amb_ocean': ocean(dur),
        'amb_fire': fire(dur),
        'amb_night_forest': crickets(dur),
        'amb_stream': stream(dur),
        'amb_brown_noise': norm(brown(int(dur * SR)), 0.6),
        'amb_pink_noise': norm(pink(int(dur * SR)), 0.5),
        'amb_white_noise': norm(fast_lowpass(white(int(dur * SR)), 8000), 0.35),
        'amb_droplets': norm(rain(dur) * 0.3 + birds(dur) * 0.0 + 0.6 * melody(
            [('E6', 1), (None, 3), ('B5', 1), (None, 2), ('G6', 1), (None, 4)], 0.3, dur, bright=1.4, swell=False), 0.6),
    }


def write_mp3(name, x, loop):
    if loop:
        x = loopable(x)
    x = norm(x, 0.85)
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        path = f.name
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(OUT, name + '.mp3')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path, '-codec:a', 'libmp3lame', '-b:a', '48k', out],
                   check=True)
    os.unlink(path)
    print(f'{out}  {len(x) / SR:.1f}s  {os.path.getsize(out) // 1024} KB')


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, x in alarms().items():
        write_mp3(name, x, loop=False)
    for name, x in ambiences().items():
        write_mp3(name, x, loop=True)


if __name__ == '__main__':
    sys.exit(main())
