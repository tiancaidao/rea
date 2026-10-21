"""
Accelerometer movement detection for a sleep tracker.

Original implementation built from standard, well-known signal-processing
techniques for phone-on-mattress movement sensing. It is not ported from any
other app; the parameters below are our own sensible defaults and are meant to
be tuned against your own recordings.

Idea (common to any movement-based sleep tracker):
  - sample the accelerometer at a modest rate while the phone rests on the bed,
  - remove the constant gravity component,
  - treat the remaining per-sample variation as "movement",
  - aggregate movement into fixed epochs (we use 30 s, the standard sleep epoch).
"""
from __future__ import annotations
from dataclasses import dataclass, field
import math

GRAVITY = 9.80665
DEFAULT_SAMPLE_HZ = 50          # a round, standard rate; plenty for body movement
DEFAULT_EPOCH_SECONDS = 30      # standard polysomnography epoch length


@dataclass
class MovementConfig:
    sample_hz: int = DEFAULT_SAMPLE_HZ
    epoch_seconds: int = DEFAULT_EPOCH_SECONDS
    # a movement "spike" is a per-sample change in acceleration (in g) above this.
    # start conservative and calibrate down to the quietest observed level.
    spike_threshold_g: float = 0.03


@dataclass
class MovementAggregator:
    """Streams accelerometer samples in and emits one movement value per epoch."""
    config: MovementConfig = field(default_factory=MovementConfig)
    _prev_mag: float | None = None
    _epoch_samples: int = 0
    _epoch_spikes: int = 0
    _epoch_energy: float = 0.0
    _epoch_index: int = 0

    @property
    def _samples_per_epoch(self) -> int:
        return self.config.sample_hz * self.config.epoch_seconds

    def add_sample(self, x: float, y: float, z: float) -> tuple[int, float] | None:
        """Feed one raw accelerometer sample (m/s^2). Returns (epoch_index,
        movement_amount) once an epoch completes, else None."""
        mag_g = math.sqrt(x * x + y * y + z * z) / GRAVITY
        if self._prev_mag is not None:
            delta = abs(mag_g - self._prev_mag)
            self._epoch_energy += delta
            if delta > self.config.spike_threshold_g:
                self._epoch_spikes += 1
        self._prev_mag = mag_g
        self._epoch_samples += 1

        if self._epoch_samples >= self._samples_per_epoch:
            # movement amount = spike rate weighted by average energy; normalized later
            amount = self._epoch_spikes + self._epoch_energy
            out = (self._epoch_index, amount)
            self._epoch_index += 1
            self._epoch_samples = 0
            self._epoch_spikes = 0
            self._epoch_energy = 0.0
            return out
        return None


def calibrate_threshold(quiet_window_g: list[float], safety: float = 1.5) -> float:
    """Pick a spike threshold from a quiet baseline recording: a small multiple
    of the typical sample-to-sample variation when the user is still."""
    if len(quiet_window_g) < 2:
        return MovementConfig().spike_threshold_g
    deltas = [abs(quiet_window_g[i] - quiet_window_g[i - 1]) for i in range(1, len(quiet_window_g))]
    deltas.sort()
    median = deltas[len(deltas) // 2]
    return max(median * safety, 0.005)
