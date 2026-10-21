#!/usr/bin/env bash
# Provision and deploy the backend to a Google Cloud / Firebase project.
#
#   scripts/deploy.sh <project-id> [--account you@example.com] [--region asia-southeast1]
#                     [--database sleep-tracker] [--audio-dir ../flutter_app/assets/audio]
#                     [--play-package com.example.sleep_tracker]
#                     [--create --billing <ACCOUNT_ID>]
#
# Safe in a project shared with other apps: data lives in its own named
# Firestore database (rules deployed to that database only), media in its own
# private bucket served via signed URLs (no Storage rules are changed), and the
# app is registered as a separate Android app. Only Firebase Auth is shared.
# Idempotent: re-running updates rules, the API and the seed data.
set -euo pipefail

PROJECT="${1:?usage: deploy.sh <project-id> [options]}"; shift
REGION="asia-southeast1"; DATABASE="sleep-tracker"
CREATE=0; BILLING=""; AUDIO_DIR=""; PLAY_PACKAGE=""; ACCOUNT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --create) CREATE=1 ;;
    --billing) BILLING="$2"; shift ;;
    --region) REGION="$2"; shift ;;
    --database) DATABASE="$2"; shift ;;
    --audio-dir) AUDIO_DIR="$2"; shift ;;
    --play-package) PLAY_PACKAGE="$2"; shift ;;
    --account) ACCOUNT="$2"; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ACCT=(); [ -n "$ACCOUNT" ] && ACCT=(--account="$ACCOUNT")
G() { gcloud --project="$PROJECT" --quiet "${ACCT[@]}" "$@"; }
BUCKET="$PROJECT-sleep-aid"
SA="sleep-tracker-api@$PROJECT.iam.gserviceaccount.com"
PKG="com.example.sleep_tracker"

if [ "$CREATE" = 1 ]; then
  [ -n "$BILLING" ] || { echo "--create needs --billing <ACCOUNT_ID>"; exit 2; }
  echo "▸ creating project $PROJECT"
  gcloud "${ACCT[@]}" projects create "$PROJECT" --name="Sleep Tracker" --quiet
  gcloud "${ACCT[@]}" billing projects link "$PROJECT" --billing-account="$BILLING" --quiet
  firebase projects:addfirebase "$PROJECT"
fi

echo "▸ billing check"
[ "$(G billing projects describe "$PROJECT" --format='value(billingEnabled)')" = "True" ] \
  || { echo "billing is not enabled on $PROJECT — link a billing account first"; exit 1; }

echo "▸ enabling APIs"
G services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  firestore.googleapis.com identitytoolkit.googleapis.com storage.googleapis.com \
  iamcredentials.googleapis.com androidpublisher.googleapis.com

echo "▸ Firestore database '$DATABASE' ($REGION)"
G firestore databases describe --database="$DATABASE" >/dev/null 2>&1 || \
  G firestore databases create --database="$DATABASE" --location="$REGION" --type=firestore-native

echo "▸ media bucket gs://$BUCKET (private)"
G storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  G storage buckets create "gs://$BUCKET" --location="$REGION" --uniform-bucket-level-access \
    --public-access-prevention

echo "▸ Auth: email/password sign-in"
TOKEN="$(gcloud "${ACCT[@]}" auth print-access-token)"
curl -sf -X PATCH -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  -H 'content-type: application/json' \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/config?updateMask=signIn.email.enabled,signIn.email.passwordRequired" \
  >/dev/null || echo "  ! enable Email/Password in the console: Authentication › Sign-in method"

echo "▸ Android app $PKG"
firebase apps:list android --project "$PROJECT" | grep -q "$PKG" 2>/dev/null || \
  firebase apps:create android "Sleep Tracker (prototype)" --package-name "$PKG" --project "$PROJECT"

echo "▸ Firestore rules → $DATABASE only"
(cd "$HERE" && firebase deploy --config firebase.deploy.json --only firestore --project "$PROJECT" --non-interactive)

echo "▸ API service account + least-privilege roles"
G iam service-accounts describe "$SA" >/dev/null 2>&1 || \
  G iam service-accounts create sleep-tracker-api --display-name="Sleep Tracker API"
G projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" \
  --role=roles/datastore.user --condition=None >/dev/null
G projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" \
  --role=roles/firebaseauth.admin --condition=None >/dev/null
G storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$SA" \
  --role=roles/storage.objectViewer >/dev/null
# sign Storage URLs as itself (v4 signed URLs via IAM signBlob)
G iam service-accounts add-iam-policy-binding "$SA" --member="serviceAccount:$SA" \
  --role=roles/iam.serviceAccountTokenCreator >/dev/null

echo "▸ Cloud Run: sleep-tracker-api ($REGION)"
ENV="STORAGE_BUCKET=$BUCKET,GOOGLE_CLOUD_PROJECT=$PROJECT,FIRESTORE_DATABASE=$DATABASE"
[ -n "$PLAY_PACKAGE" ] && ENV="$ENV,PLAY_PACKAGE_NAME=$PLAY_PACKAGE"
# public ingress: every /v1 route verifies a Firebase ID token itself
G run deploy sleep-tracker-api --source="$HERE/api" --region="$REGION" \
  --service-account="$SA" --allow-unauthenticated --set-env-vars="$ENV" \
  --min-instances=0 --max-instances=3 --memory=512Mi
URL="$(G run services describe sleep-tracker-api --region="$REGION" --format='value(status.url)')"

echo "▸ seed config + sleep-aid catalog"
SEED_ARGS=(--project "$PROJECT" --bucket "$BUCKET" --database "$DATABASE")
[ -n "$AUDIO_DIR" ] && SEED_ARGS+=(--audio-dir "$AUDIO_DIR")
ACCESS_TOKEN="$(gcloud "${ACCT[@]}" auth print-access-token)" node "$HERE/scripts/seed.js" "${SEED_ARGS[@]}"

echo
echo "✔ deployed. API: $URL"
echo "  Health: curl $URL/healthz"
echo "  App flags: scripts/app_defines.sh $PROJECT $URL"
