#!/usr/bin/env bash
# Repopulate the local comparison placeholders from a Sleep Cycle APK.
#
# These assets are Northcube's copyrighted material. They are gitignored and
# used ONLY to build a side-by-side UX comparison on your own machine — never
# committed, published, or shipped. Run against an APK you have the right to
# analyse.
#
#   ./tools/extract_placeholders.sh /path/to/com.northcube.sleepcycle.apk
set -euo pipefail
APK="${1:?usage: extract_placeholders.sh <apk>}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/assets"
mkdir -p "$DEST"/{lottie,audio,data,icon}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

unzip -o -j "$APK" \
  "res/raw/rain_and_wind.mp3" "res/raw/gentle_dawn.mp3" \
  "res/raw/morning_drops.mp3" "res/raw/mozarts_morning.mp3" \
  -d "$DEST/audio" >/dev/null

unzip -o -j "$APK" "res/raw/sleep_aid_index.json" "res/raw/stars.csv" \
  "res/raw/night_stars.csv" -d "$DEST/data" >/dev/null

unzip -o -j "$APK" "res/mipmap-xxxhdpi-v4/ic_launcher_round.png" -d "$tmp" >/dev/null
mv "$tmp/ic_launcher_round.png" "$DEST/icon/app_icon.png"

# dotLottie (zip) -> inner animation json
unzip -o -j "$APK" "res/raw/animated_onboarding.lottie" -d "$tmp" >/dev/null
unzip -o "$tmp/animated_onboarding.lottie" "animations/*" -d "$tmp/ob" >/dev/null
mv "$tmp"/ob/animations/*.json "$DEST/lottie/animated_onboarding.json"

unzip -o -j "$APK" "res/raw/anim_soundwaves.json" -d "$tmp" >/dev/null
mv "$tmp/anim_soundwaves.json" "$DEST/lottie/soundwaves.json"

echo "Placeholders written to $DEST"
echo "NOTE: strings.en.json (real UI copy) is produced separately from the APK"
echo "      string table; the repo ships strings.en.sample.json (original copy)."
