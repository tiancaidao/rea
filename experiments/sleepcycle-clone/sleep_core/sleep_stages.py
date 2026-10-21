"""
Sleep-stage estimation from per-epoch features.

Original implementation using a standard, transparent approach: map each epoch
to a "sleep depth" from its movement (and optional breathing) features, smooth
the depth curve, and bucket it into the conventional stages. This is a baseline
you can later replace with a learned model trained on your own labelled data.

Stages (standard): AWAKE, REM, LIGHT, DEEP.
"""
from __future__ import annotations
from dataclasses import dataclass
import math

STAGES = ("deep", "light", "rem", "awake")  # index = depth level 0..3


@dataclass
class EpochFeatures:
    movement: float                 # normalized 0..1 movement amount
    breathing_rate: float | None = None     # breaths/min, if available
    breathing_conf: float = 0.0     # 0..1 confidence in the breathing estimate


def _gaussian_kernel(radius: int, sigma: float) -> list[float]:
    ks = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-radius, radius + 1)]
    s = sum(ks)
    return [k / s for k in ks]


def _smooth(xs: list[float], radius: int, sigma: float) -> list[float]:
    if not xs:
        return xs
    k = _gaussian_kernel(radius, sigma)
    out = []
    for i in range(len(xs)):
        acc = 0.0
        for j, w in enumerate(k):
            idx = min(max(i + j - radius, 0), len(xs) - 1)
            acc += xs[idx] * w
        out.append(acc)
    return out


def estimate_stages(
    epochs: list[EpochFeatures],
    smooth_radius: int = 5,
    smooth_sigma: float = 2.0,
    tail_awake_epochs: int = 6,
) -> list[str]:
    """Return a stage label per epoch.

    depth 0 = deep, 3 = awake. We build a continuous depth signal from movement
    (more movement -> shallower sleep), optionally nudged by breathing variability,
    smooth it, then bucket. The final few epochs are forced to AWAKE (people are
    awake just before they stop a tracking session)."""
    if not epochs:
        return []

    # raw depth: still -> deep (0), active -> awake (3)
    raw = [3.0 * min(max(e.movement, 0.0), 1.0) for e in epochs]

    # if breathing is confidently available, steady breathing deepens sleep a touch
    for i, e in enumerate(epochs):
        if e.breathing_rate is not None and e.breathing_conf > 0.3:
            raw[i] = max(0.0, raw[i] - 0.3)

    depth = _smooth(raw, smooth_radius, smooth_sigma)

    labels: list[str] = []
    for d in depth:
        level = int(round(min(max(d, 0.0), 3.0)))
        labels.append(STAGES[level])

    for i in range(max(0, len(labels) - tail_awake_epochs), len(labels)):
        labels[i] = "awake"
    return labels
