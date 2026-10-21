#!/usr/bin/env bash
# Provision and deploy the backend to a Google Cloud / Firebase project.
#
#   scripts/deploy.sh <project-id> [--create --billing <ACCOUNT_ID>] [--region asia-southeast1]
#                     [--audio-dir ../flutter_app/assets/audio] [--play-package com.example.sleep_tracker]
#
# Idempotent: re-running updates rules, the API and the seed data.
# Needs: gcloud (logged in), firebase CLI (logged in: `firebase login`), node.
set -euo pipefail

PROJECT="${1:?usage: deploy.sh <project-id> [options]}"; shift
REGION="asia-southeast1"
CREATE=0; BILLING=""; AUDIO_DIR=""; PLAY_PACKAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --create) CREATE=1 ;;
    --billing) BILLING="$2"; shift ;;
    --region) REGION="$2"; shift ;;
    --audio-dir) AUDIO_DIR="$2"; shift ;;
    --play-package) PLAY_PACKAGE="$2"; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
HERE="$(cd "$(dirname "$0")/.." && pwd)"
G="gcloud --project=$PROJECT --quiet"

if [ "$CREATE" = 1 ]; then
  [ -n "$BILLING" ] || { echo "--create needs --billing <ACCOUNT_ID>"; exit 2; }
  echo "▸ creating project $PROJECT"
  gcloud projects create "$PROJECT" --name="Sleep Tracker" --quiet
  gcloud billing projects link "$PROJECT" --billing-account="$BILLING" --quiet
fi

echo "▸ enabling APIs"
$G services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  firestore.googleapis.com firebase.googleapis.com identitytoolkit.googleapis.com \
  firebasestorage.googleapis.com storage.googleapis.com iamcredentials.googleapis.com \
  androidpublisher.googleapis.com

echo "▸ adding Firebase"
firebase projects:addfirebase "$PROJECT" 2>/dev/null || echo "  (already a Firebase project)"

echo "▸ Firestore (native mode, $REGION)"
$G firestore databases describe --database='(default)' >/dev/null 2>&1 || \
  $G firestore databases create --location="$REGION" --type=firestore-native

echo "▸ default Storage bucket"
TOKEN="$(gcloud auth print-access-token)"
BUCKET="$PROJECT.firebasestorage.app"
curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H 'content-type: application/json' -d "{\"location\":\"$REGION\"}" \
  "https://firebasestorage.googleapis.com/v1alpha/projects/$PROJECT/defaultBucket" >/dev/null \
  || echo "  (bucket exists or must be created once in the console: Build › Storage › Get started)"

echo "▸ Auth: enable email/password sign-in"
curl -sf -X PATCH -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H 'content-type: application/json' \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/config?updateMask=signIn.email" >/dev/null \
  || echo "  (enable Email/Password once in the console: Build › Authentication › Sign-in method)"

echo "▸ Android app registration"
firebase apps:list android --project "$PROJECT" 2>/dev/null | grep -q com.example.sleep_tracker || \
  firebase apps:create android "Sleep Tracker" --package-name com.example.sleep_tracker --project "$PROJECT"

echo "▸ security rules"
(cd "$HERE" && firebase deploy --only firestore:rules,firestore:indexes,storage --project "$PROJECT" --non-interactive)

echo "▸ API service account + roles"
SA="sleep-tracker-api@$PROJECT.iam.gserviceaccount.com"
$G iam service-accounts describe "$SA" >/dev/null 2>&1 || \
  $G iam service-accounts create sleep-tracker-api --display-name="Sleep Tracker API"
for role in roles/datastore.user roles/firebaseauth.admin roles/storage.objectViewer; do
  $G projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" --role="$role" >/dev/null
done
# lets the API sign Storage URLs as itself (v4 signed URLs via IAM signBlob)
$G iam service-accounts add-iam-policy-binding "$SA" --member="serviceAccount:$SA" \
  --role=roles/iam.serviceAccountTokenCreator >/dev/null

echo "▸ Cloud Run: sleep-tracker-api ($REGION)"
ENV="STORAGE_BUCKET=$BUCKET,GOOGLE_CLOUD_PROJECT=$PROJECT"
[ -n "$PLAY_PACKAGE" ] && ENV="$ENV,PLAY_PACKAGE_NAME=$PLAY_PACKAGE"
# public ingress: every /v1 route verifies a Firebase ID token itself
$G run deploy sleep-tracker-api --source="$HERE/api" --region="$REGION" \
  --service-account="$SA" --allow-unauthenticated --set-env-vars="$ENV" \
  --min-instances=0 --max-instances=3 --memory=512Mi
URL="$($G run services describe sleep-tracker-api --region="$REGION" --format='value(status.url)')"

echo "▸ seed config + sleep-aid catalog"
SEED_ARGS=(--project "$PROJECT" --bucket "$BUCKET")
[ -n "$AUDIO_DIR" ] && SEED_ARGS+=(--audio-dir "$AUDIO_DIR")
node "$HERE/scripts/seed.js" "${SEED_ARGS[@]}"

echo
echo "✔ deployed. API: $URL"
echo "  Health: curl $URL/healthz"
echo "  App flags: scripts/app_defines.sh $PROJECT $URL"
