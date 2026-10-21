"""
Smart alarm: wake the user at a light moment inside a window before their set
alarm time.

Original implementation of the standard idea behind every "smart alarm": over a
wake window (e.g. the 30 min before the hard alarm), fire when the user looks
like they're in light sleep (relatively high recent movement), and guarantee
firing by the window end. Thresholds are learned from the night's own movement
distribution so they adapt per user and per night.
"""
from __future__ import annotations
from dataclasses import dataclass


def _percentile(sorted_xs: list[float], p: float) -> float:
    if not sorted_xs:
        return 0.0
    k = (len(sorted_xs) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(sorted_xs) - 1)
    return sorted_xs[lo] + (sorted_xs[hi] - sorted_xs[lo]) * (k - lo)


@dataclass
class SmartAlarm:
    window_minutes: int = 30          # how long before the hard alarm to start looking
    high_percentile: float = 0.90     # "clearly moving" level for this night
    low_percentile: float = 0.50      # relax toward the median as the window runs out

    def thresholds(self, night_movement: list[float]) -> tuple[float, float]:
        xs = sorted(night_movement)
        return _percentile(xs, self.high_percentile), _percentile(xs, self.low_percentile)

    def should_fire(
        self,
        minute_in_window: int,
        recent_movement: float,
        night_movement: list[float],
    ) -> bool:
        """Call once per minute inside the wake window.

        The firing threshold eases linearly from the night's high level down to
        its median across the window, so late in the window a smaller stir is
        enough; at the end it always fires."""
        if minute_in_window >= self.window_minutes:
            return True
        high, low = self.thresholds(night_movement)
        frac = minute_in_window / max(self.window_minutes, 1)
        threshold = high + (low - high) * frac
        return recent_movement >= threshold
