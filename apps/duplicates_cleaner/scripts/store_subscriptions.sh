#!/bin/bash
# Create or update the app's subscriptions on Google Play or the App Store
# from store_products/subscriptions.json.
#
# Usage: scripts/store_subscriptions.sh <play|ios> <list|sync> [options]
#   list   show the subscriptions the store has now
#   sync   create or update them to match the file (dry run unless --apply)
# Options: --apply, --only PRODUCT_ID, --update-prices (and for ios
# --no-preserve-price). See store_products/README.md.
#
# ios reads the App Store Connect API key from fastlane/.env, the same one
# scripts/publish_ios.sh uses. play reads google_play/google-play-credentials.json
# (or PLAY_KEY_FILE).

set -euo pipefail

STORE="${1:-}"
case "$STORE" in
  play) SCRIPT=play_subscriptions.py ;;
  ios) SCRIPT=asc_subscriptions.py ;;
  -h|--help|"") sed -n '2,13p' "$0"; exit 0 ;;
  *) echo "Unknown store '$STORE'. Use play or ios."; exit 1 ;;
esac
shift

cd "$(dirname "$0")/.."

ENV_FILE=
[[ "$STORE" == ios ]] && ENV_FILE=fastlane/.env
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

VENV=store_products/.venv
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r store_products/requirements.txt
fi

exec "$VENV/bin/python" "store_products/$SCRIPT" "$@"
