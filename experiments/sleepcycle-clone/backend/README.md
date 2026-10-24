# Backend: Firebase + Cloud Run

Replaces `../mock-api` with real services.

| Piece     | Service                              | What it does                                                                                                                                                                                                                                                                                                                                                                               |
| --------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sign-in   | **Firebase Auth**                    | email/password (Google sign-in once the app's SHA-1 is registered)                                                                                                                                                                                                                                                                                                                         |
| User data | **Firestore**                        | `users/{uid}` profile + settings, `users/{uid}/nights/{id}` one doc per night, `users/{uid}/reports/{week}`; owner-only rules, `premium` server-written                                                                                                                                                                                                                                    |
| Media     | **Cloud Storage**                    | `sleep-aid/audio/*`, signed-in read only; the API hands out 1-h signed URLs                                                                                                                                                                                                                                                                                                                |
| API       | **Cloud Run** (`api/`, Node/Express) | `/v1/config` (remote config + paywall), `/v1/sleep-aid/catalog`, `/v1/insights/weekly`, `/v1/weather` (Open-Meteo, coords rounded to ~10 km), `/v1/billing/verify` (Google Play subscriptions v2), `/v1/trial/start`, `/v1/giftcards/redeem`, `/v1/insights/recommendations`, `/v1/consent`, `/v1/user/properties`, `/v1/devices/register`, `/v1/account/erase-data`, `/v1/account/delete` |

Every `/v1` route except config verifies a Firebase ID token. The app reads/writes
its own data directly in Firestore; the API does what needs a server (signing,
cross-night insights, third-party calls, privileged writes).

## Run locally (no cloud account needed)

Requires JDK 21 for the emulators (Android Studio's bundled JBR works:
`export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`).

```bash
cd backend
(cd api && npm install)
npm run emulators          # Auth :9099, Firestore :8085, Storage :9199, UI :4000
npm run seed:emulators     # config + catalog; uploads ../flutter_app/assets/audio if present
npm run api:emulators      # API on :8080
(cd api && npm test)       # unit + end-to-end tests against the emulators (incl. security rules)

cd ../flutter_app
flutter run --dart-define=BACKEND=emulator   # Android emulator reaches the host at 10.0.2.2
```

## Deploy

```bash
firebase login                      # once
scripts/deploy.sh <project-id> [--account you@example.com] \
  --audio-dir ../flutter_app/assets/audio          # optional: your local media
scripts/app_defines.sh <project-id> <api-url> --json > ../flutter_app/config/backend.cloud.json
cd ../flutter_app && flutter run --dart-define-from-file=config/backend.cloud.json
```

`config/backend.cloud.json` is gitignored: this repo is public, and the
project config would let anyone create accounts in your Firebase project.
See `config/backend.example.json` for the shape.

Shared projects are fine: the backend uses its own Firestore database
(`sleep-tracker`), its own private bucket (`<project>-sleep-aid`) and its own
Android app registration; it doesn't change other apps' rules or data.
Cloud Run reserves `/healthz`, so use `GET /health`.

`deploy.sh` checks billing, enables the APIs, creates the named Firestore
database and the private media bucket, enables email sign-in, registers the Android app, deploys rules, creates
a least-privilege service account, deploys the API to Cloud Run (scale-to-zero,
max 3 instances) and seeds the catalog. Re-run it to update.

Uploaded audio goes to a private path readable only by signed-in users of your
own project. Keep it that way: the bundled placeholders are third-party content
for private testing.

### Still to connect by hand

- **Google sign-in:** add the debug/release SHA-1 to the Android app in the
  Firebase console, enable the Google provider, then wire `google_sign_in`.
- **Play Billing:** publish the app to an internal test track with a
  `premium_yearly` subscription, grant the API's service account access in Play
  Console (Users & permissions), and deploy with `--play-package <id>`. Until
  then the app reports that the product isn't set up and starts a local trial;
  nothing is charged.
