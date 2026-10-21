#!/usr/bin/env bash
# Print the --dart-define flags that point the Flutter app at a deployed
# project, from the Firebase Android app's SDK config.
#
#   flutter run $(backend/scripts/app_defines.sh <project-id> <api-url>)
set -euo pipefail
PROJECT="${1:?usage: app_defines.sh <project-id> <api-url>}"
API="${2:?usage: app_defines.sh <project-id> <api-url>}"
APP_ID="$(firebase apps:list android --project "$PROJECT" | grep com.example.sleep_tracker | grep -oE '1:[0-9]+:android:[0-9a-f]+' | head -1)"
CFG="$(firebase apps:sdkconfig android "$APP_ID" --project "$PROJECT")"
pick() { python3 -c "import json,sys;j=json.load(sys.stdin);c=j['client'][0];print($1)" <<<"$CFG"; }
echo "--dart-define=BACKEND=cloud" \
  "--dart-define=API_BASE_URL=$API" \
  "--dart-define=FIREBASE_PROJECT_ID=$PROJECT" \
  "--dart-define=FIREBASE_APP_ID=$APP_ID" \
  "--dart-define=FIREBASE_API_KEY=$(pick "c['api_key'][0]['current_key']")" \
  "--dart-define=FIREBASE_SENDER_ID=$(pick "j['project_info']['project_number']")" \
  "--dart-define=FIREBASE_STORAGE_BUCKET=$(pick "j['project_info']['storage_bucket']")"
