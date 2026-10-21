#!/usr/bin/env bash
# Repopulate ALL local comparison placeholders from a Sleep Cycle APK.
#
# These assets are Northcube's copyrighted material (and the fonts are
# separately licensed). They are gitignored and used ONLY to build/compare on
# your own machine — never committed, published, or shipped. Run against an APK
# you have the right to analyse.
#
#   ./tools/extract_placeholders.sh /path/to/com.northcube.sleepcycle.apk
set -euo pipefail
APK="${1:?usage: extract_placeholders.sh <apk>}"
ASSETS="$(cd "$(dirname "$0")/.." && pwd)/assets"
mkdir -p "$ASSETS"/{lottie,audio,video,data,icon,images,fonts}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jj() { unzip -o -j "$APK" "$@" >/dev/null 2>&1 || true; }  # junk-paths extract, tolerant

echo "audio (alarm sounds + ambiences)…"
jj 'res/raw/*.mp3' 'res/raw/*.ogg' -d "$ASSETS/audio"

echo "video…"
jj 'res/raw/*.mp4' -d "$ASSETS/video"

echo "images (illustrations, moon sequence, weather/cloud backgrounds, icons)…"
jj 'res/drawable-nodpi*/*.webp' 'res/drawable-nodpi*/*.png' 'res/drawable-nodpi*/*.jpg' -d "$ASSETS/images"
jj 'res/drawable-xxhdpi*/*.webp' 'res/drawable-xxhdpi*/*.png' -d "$ASSETS/images"

echo "fonts (rounded brand font, for reference — check licensing before any real use)…"
jj 'res/font/*.otf' 'res/font/*.ttf' -d "$ASSETS/fonts"

echo "icon…"
jj 'res/mipmap-xxxhdpi-v4/ic_launcher_round.png' -d "$tmp"
[ -f "$tmp/ic_launcher_round.png" ] && mv "$tmp/ic_launcher_round.png" "$ASSETS/icon/app_icon.png"

echo "data (sleep-aid catalog, star fields)…"
jj 'res/raw/sleep_aid_index.json' 'res/raw/stars.csv' 'res/raw/night_stars.csv' -d "$ASSETS/data"

echo "lottie / vector animations…"
jj 'res/raw/anim_*.json' 'res/raw/animation_*.json' -d "$ASSETS/lottie"
mv -f "$ASSETS/lottie/anim_soundwaves.json" "$ASSETS/lottie/soundwaves.json" 2>/dev/null || true
mv -f "$ASSETS/lottie/anim_sc_icon.json"    "$ASSETS/lottie/sc_icon.json"    2>/dev/null || true
mv -f "$ASSETS/lottie/anim_eq_loop.json"    "$ASSETS/lottie/eq_loop.json"    2>/dev/null || true
# dotLottie archives (.lottie) are zips: unpack their inner animation json
for name in animated_onboarding two_plan_paywall_anim; do
  jj "res/raw/$name.lottie" -d "$tmp"
  if [ -f "$tmp/$name.lottie" ]; then
    rm -rf "$tmp/$name"; mkdir -p "$tmp/$name"
    unzip -o "$tmp/$name.lottie" 'animations/*' -d "$tmp/$name" >/dev/null 2>&1 || true
    inner="$(find "$tmp/$name/animations" -name '*.json' 2>/dev/null | head -1)"
    [ -n "$inner" ] && cp "$inner" "$ASSETS/lottie/$name.json"
  fi
done

echo
echo "Done. Captured into $ASSETS :"
for d in audio video images fonts lottie data icon; do
  printf '  %-7s %s files\n' "$d" "$(find "$ASSETS/$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
done
echo
echo "NOTE: strings.en.json (real UI copy) is produced separately from the APK"
echo "      string table; the repo ships strings.en.sample.json (original copy)."
echo "Fonts are extracted for reference only — they are separately licensed; the"
echo "app does not wire them in. Everything here is gitignored and local-only."
