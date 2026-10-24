#!/bin/bash
# Create or update Lullwake's subscriptions on Google Play or the App Store
# from store_products/subscriptions.json.
#
# Usage: scripts/store_subscriptions.sh plan
#        scripts/store_subscriptions.sh <play|ios> <list|sync> [options]
#   plan   print what the file defines; reads no credentials, calls no store
#   list   show the subscriptions the store has now
#   sync   create or update them to match the file (dry run unless --apply)
# Options: --apply, --only PRODUCT_ID, --update-prices (and for ios
# --no-preserve-price). See store_products/README.md.
#
# Credentials are never stored here. store_products/.env (gitignored) may set
#   ASC_ENV_FILE    a file with ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH
#                   (a relative ASC_KEY_PATH is read next to that file)
#   PLAY_KEY_FILE   the Play service account JSON key
# or export ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH and PLAY_KEY_FILE yourself.

set -euo pipefail

STORE="${1:-}"
case "$STORE" in
  plan) SCRIPT=products.py ;;
  play) SCRIPT=play_subscriptions.py ;;
  ios) SCRIPT=asc_subscriptions.py ;;
  -h|--help|"") sed -n '2,17p' "$0"; exit 0 ;;
  *) echo "Unknown command '$STORE'. Use plan, play or ios."; exit 1 ;;
esac
shift

cd "$(dirname "$0")"

if [[ "$STORE" != plan && -f store_products/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source store_products/.env
  set +a
fi

if [[ "$STORE" == ios && -n "${ASC_ENV_FILE:-}" ]]; then
  ASC_ENV_FILE="${ASC_ENV_FILE/#\~/$HOME}"
  [[ -f "$ASC_ENV_FILE" ]] || { echo "ASC_ENV_FILE not found: $ASC_ENV_FILE"; exit 1; }
  set -a
  # shellcheck disable=SC1090
  source "$ASC_ENV_FILE"
  set +a
  ASC_KEY_PATH="${ASC_KEY_PATH:-}"
  ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
  if [[ -n "$ASC_KEY_PATH" && "$ASC_KEY_PATH" != /* ]]; then
    ASC_KEY_PATH="$(cd "$(dirname "$ASC_ENV_FILE")" && pwd)/$ASC_KEY_PATH"
  fi
  export ASC_KEY_PATH
fi
[[ -n "${PLAY_KEY_FILE:-}" ]] && export PLAY_KEY_FILE="${PLAY_KEY_FILE/#\~/$HOME}"

VENV=store_products/.venv
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r store_products/requirements.txt
fi

exec "$VENV/bin/python" "store_products/$SCRIPT" "$@"
