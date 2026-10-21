"""
sleep_core: original, portable sleep-tracking algorithms.

Plain, framework-neutral logic (easy to port to Dart/Kotlin/Swift) built from
standard signal-processing techniques. Not ported from any other app. ML stages
are pluggable — you supply your own trained models.

Modules:
  movement      - accelerometer movement detection + calibration
  sleep_stages  - per-epoch feature -> AWAKE/REM/LIGHT/DEEP with smoothing
  smart_alarm   - adaptive wake-window firing from the night's movement
  snore         - snore event post-processing + "who is snoring" kNN vote
"""
