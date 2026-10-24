#!/bin/bash
# Build the release AAB and upload it to Google Play.
#
# Usage: scripts/publish_android.sh [track]      track: internal (default) | alpha | beta | production
#
# Needs google_play/google-play-credentials.json (gitignored) and
# android/keystore.properties for release signing. Set BUILD_NUMBER=N to force
# a version code, RELEASE_STATUS=draft for a draft release, or RELEASE_NOTES="...".

set -euo pipefail

TRACK="${1:-internal}"
cd "$(dirname "$0")/.."

UPLOADER=google_play/upload_to_google_play.py
VENV=google_play/.venv

if [[ ! -f android/keystore.properties ]]; then
  echo "ERROR: android/keystore.properties is missing, so the AAB can't be release-signed."
  exit 1
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r google_play/requirements.txt
fi
PY="$VENV/bin/python"

if [[ -z "${BUILD_NUMBER:-}" ]]; then
  pubspec_build=$(grep '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
  latest=$("$PY" "$UPLOADER" --get-latest-version | sed -n 's/^LATEST_VERSION_CODE=//p')
  BUILD_NUMBER=$(( pubspec_build > latest + 1 ? pubspec_build : latest + 1 ))
fi
echo "Building AAB with version code $BUILD_NUMBER"

flutter pub get
flutter build appbundle --release --build-number "$BUILD_NUMBER"

args=(--track "$TRACK" --status "${RELEASE_STATUS:-completed}")
[[ -n "${RELEASE_NOTES:-}" ]] && args+=(--release-notes "$RELEASE_NOTES")
exec "$PY" "$UPLOADER" "${args[@]}"
