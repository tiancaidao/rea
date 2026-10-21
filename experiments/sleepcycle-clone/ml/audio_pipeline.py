"""
Reference audio pipeline for a Sleep Cycle-style snore/sound tracker.

This re-implements the *interface* reverse-engineered from the shipped app
(com.northcube.sleepcycle 4.26.37), NOT its trained weights. The exact tensor
shapes below were read from the app's unencrypted `fft_model.tflite` and
`snoracle-*.tflite`; you train your own CNN to produce the embedding.

Pipeline (matches the app's three-model chain):

    raw PCM @ 44100 Hz
      -> frame into 2048-sample windows            (fft_model input  [1, 2048])
      -> real FFT magnitude, 1025 bins             (fft_model output [1, 1025])
      -> mel filterbank -> 64 mel bins, 86 frames  (== app's audio_to_mel_spectrogram.ort, encrypted)
      -> CNN -> 128-D L2-normalized embedding       (snoracle input [1,1,86,64] -> output [1,1,128])
      -> compare embedding to a per-user snore signature   (== app's snore_signature.ort, encrypted)

Everything here is standard DSP + a small CNN; the value Northcube protects is
the *trained weights* and the labelled dataset, which you build yourself.
"""
from __future__ import annotations
import numpy as np

SAMPLE_RATE = 44100      # observed constant in logic.snore / sleepanalysis
FFT_SIZE = 2048          # fft_model.tflite input  -> [1, 2048]
FFT_BINS = FFT_SIZE // 2 + 1   # 1025, fft_model.tflite output -> [1, 1025]
N_MELS = 64              # snoracle input mel bins
N_FRAMES = 86            # snoracle input time frames  ([1, 1, 86, 64])
EMBED_DIM = 128          # snoracle output embedding    ([1, 1, 128])
HOP = 1024               # window hop (512/1024 seen as constants)


def frame_signal(pcm: np.ndarray, frame: int = FFT_SIZE, hop: int = HOP) -> np.ndarray:
    """Slice mono PCM into overlapping analysis windows -> (n_frames, frame)."""
    if pcm.ndim != 1:
        raise ValueError("expected mono PCM")
    n = 1 + max(0, (len(pcm) - frame) // hop)
    out = np.empty((n, frame), dtype=np.float32)
    for i in range(n):
        out[i] = pcm[i * hop: i * hop + frame]
    return out * np.hanning(frame).astype(np.float32)


def magnitude_spectrum(frames: np.ndarray) -> np.ndarray:
    """(n_frames, 2048) -> (n_frames, 1025) real-FFT magnitudes (== fft_model)."""
    return np.abs(np.fft.rfft(frames, n=FFT_SIZE, axis=-1)).astype(np.float32)


def _mel_filterbank(sr: int = SAMPLE_RATE, n_fft: int = FFT_SIZE, n_mels: int = N_MELS) -> np.ndarray:
    """Slaney-style mel filterbank -> (n_mels, 1025). Replaces the encrypted ORT model."""
    def hz_to_mel(f): return 2595.0 * np.log10(1.0 + f / 700.0)
    def mel_to_hz(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    fmin, fmax = 0.0, sr / 2.0
    mels = np.linspace(hz_to_mel(fmin), hz_to_mel(fmax), n_mels + 2)
    freqs = mel_to_hz(mels)
    bins = np.floor((n_fft + 1) * freqs / sr).astype(int)
    fb = np.zeros((n_mels, n_fft // 2 + 1), dtype=np.float32)
    for m in range(1, n_mels + 1):
        l, c, r = bins[m - 1], bins[m], bins[m + 1]
        for k in range(l, c):
            if c != l:
                fb[m - 1, k] = (k - l) / (c - l)
        for k in range(c, r):
            if r != c:
                fb[m - 1, k] = (r - k) / (r - c)
    return fb


def mel_spectrogram(pcm: np.ndarray) -> np.ndarray:
    """PCM -> (N_FRAMES, N_MELS) log-mel patch ready for the CNN."""
    mag = magnitude_spectrum(frame_signal(pcm))          # (frames, 1025)
    mel = mag @ _mel_filterbank().T                       # (frames, 64)
    logmel = np.log(np.maximum(mel, 1e-10))
    # center/crop to exactly N_FRAMES so the tensor is [1,1,86,64]
    if len(logmel) >= N_FRAMES:
        logmel = logmel[:N_FRAMES]
    else:
        logmel = np.pad(logmel, ((0, N_FRAMES - len(logmel)), (0, 0)))
    return logmel.astype(np.float32)


def to_cnn_tensor(logmel: np.ndarray) -> np.ndarray:
    """(86, 64) -> (1, 1, 86, 64) NCHW, the Snoracle input shape."""
    return logmel[None, None, :, :]


# --- Your own model goes here. Shape contract is fixed by the RE above. ---
# import torch, torch.nn as nn
# class Snoracle(nn.Module):
#     """7x [Conv2d -> BatchNorm2d -> ReLU -> Dropout] -> GAP -> Linear(128), L2-normalized.
#        Matches the shipped graph's structure; train with triplet loss on your data."""
#     ...
# embedding = F.normalize(model(torch.from_numpy(to_cnn_tensor(mel))), dim=-1)  # (1,1,128)


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    a, b = a.ravel(), b.ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


if __name__ == "__main__":
    # smoke test: 2 seconds of noise through the front-end
    pcm = (np.random.randn(SAMPLE_RATE * 2) * 0.1).astype(np.float32)
    mel = mel_spectrogram(pcm)
    t = to_cnn_tensor(mel)
    assert t.shape == (1, 1, N_FRAMES, N_MELS), t.shape
    print("mel patch:", mel.shape, "-> CNN tensor:", t.shape, "-> embedding dim:", EMBED_DIM)
