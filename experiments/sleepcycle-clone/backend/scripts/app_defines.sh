#!/usr/bin/env bash
# Print the --dart-define flags that point the Flutter app at a deployed
# project, from the Firebase Android app's SDK config.
#
#   flutter run $(backend/scripts/app_defines.sh <project-id> <api-url>)
#   backend/scripts/app_defines.sh <project-id> <api-url> --json > flutter_app/config/backend.cloud.json
#   flutter run --dart-define-from-file=config/backend.cloud.json
set -euo pipefail
JSON=0; [ "${3:-}" = "--json" ] && JSON=1
PROJECT="${1:?usage: app_defines.sh <project-id> <api-url>}"
API="${2:?usage: app_defines.sh <project-id> <api-url>}"
APP_ID="$(firebase apps:list android --project "$PROJECT" | grep 'Sleep Tracker (prototype)' | grep -oE '1:[0-9]+:android:[0-9a-f]+' | head -1)"
CFG="$(firebase apps:sdkconfig android "$APP_ID" --project "$PROJECT")"
pick() { python3 -c "import json,sys;j=json.load(sys.stdin);c=j['client'][0];print($1)" <<<"$CFG"; }
if [ "$JSON" = 1 ]; then
  python3 - "$API" "$PROJECT" "$APP_ID" <<PY
import json,sys
c=json.loads('''$CFG''')
api,proj,app=sys.argv[1:4]
print(json.dumps({"BACKEND":"cloud","API_BASE_URL":api,"FIREBASE_PROJECT_ID":proj,"FIREBASE_APP_ID":app,
  "FIREBASE_API_KEY":c["client"][0]["api_key"][0]["current_key"],"FIREBASE_SENDER_ID":c["project_info"]["project_number"],
  "FIREBASE_STORAGE_BUCKET":c["project_info"]["storage_bucket"]},indent=2))
PY
  exit 0
fi
echo "--dart-define=BACKEND=cloud" \
  "--dart-define=API_BASE_URL=$API" \
  "--dart-define=FIREBASE_PROJECT_ID=$PROJECT" \
  "--dart-define=FIREBASE_APP_ID=$APP_ID" \
  "--dart-define=FIREBASE_API_KEY=$(pick "c['api_key'][0]['current_key']")" \
  "--dart-define=FIREBASE_SENDER_ID=$(pick "j['project_info']['project_number']")" \
  "--dart-define=FIREBASE_STORAGE_BUCKET=$(pick "j['project_info']['storage_bucket']")"
