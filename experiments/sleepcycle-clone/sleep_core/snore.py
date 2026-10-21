"""
Snore event detection from a sound model's per-frame scores.

Original, model-agnostic post-processing. You bring a sound classifier (your own
trained model) that emits a per-frame "snore" probability over short audio
frames; this turns that noisy probability stream into clean snore *events* using
standard hysteresis + minimum-duration rules. No trained weights here.
"""
from __future__ import annotations
from dataclasses import dataclass


@dataclass
class SnoreEventConfig:
    frame_seconds: float = 0.1       # duration of one model frame
    on_threshold: float = 0.5        # probability to count a frame as snore
    majority_window: int = 3         # majority-vote smoothing over N frames
    min_event_frames: int = 3        # reject blips shorter than this (~0.3 s)
    min_mean_prob: float = 0.5       # an event's average probability must clear this


@dataclass
class SnoreEvent:
    start_frame: int
    end_frame: int           # exclusive
    mean_prob: float

    def duration_seconds(self, frame_seconds: float) -> float:
        return (self.end_frame - self.start_frame) * frame_seconds


def detect_events(frame_probs: list[float], cfg: SnoreEventConfig = SnoreEventConfig()) -> list[SnoreEvent]:
    """Convert per-frame snore probabilities into discrete snore events."""
    n = len(frame_probs)
    if n == 0:
        return []

    # majority-vote smoothing: a frame is "on" if most of its neighbours are above threshold
    on = []
    half = cfg.majority_window // 2
    for i in range(n):
        votes = 0
        total = 0
        for j in range(i - half, i + half + 1):
            if 0 <= j < n:
                total += 1
                if frame_probs[j] >= cfg.on_threshold:
                    votes += 1
        on.append(votes * 2 > total)

    events: list[SnoreEvent] = []
    start = None
    for i in range(n + 1):
        active = on[i] if i < n else False
        if active and start is None:
            start = i
        elif not active and start is not None:
            seg = frame_probs[start:i]
            mean_p = sum(seg) / len(seg)
            if (i - start) >= cfg.min_event_frames and mean_p >= cfg.min_mean_prob:
                events.append(SnoreEvent(start, i, mean_p))
            start = None
    return events


def cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    return dot / (na * nb + 1e-9)


def who_is_snoring(embedding: list[float], labelled: list[tuple[list[float], str]], k: int = 3) -> str | None:
    """k-nearest-neighbour vote over labelled snore embeddings ("me" vs "other").
    Returns the winning label, or None if there aren't enough labelled samples.
    You generate `embedding` with your own trained embedding model."""
    if len(labelled) < max(k, 10):
        return None
    scored = sorted(labelled, key=lambda p: cosine_similarity(embedding, p[0]), reverse=True)
    votes: dict[str, int] = {}
    for _, label in scored[:k]:
        votes[label] = votes.get(label, 0) + 1
    return max(votes, key=votes.get)
