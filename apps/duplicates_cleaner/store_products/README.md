# Store subscriptions

`subscriptions.json` defines the app's auto-renewing subscription (Prime
Monthly). Two scripts make each store match it:

| Script | Store | API |
|---|---|---|
| `play_subscriptions.py` | Google Play | Play Developer API, `monetization.subscriptions` |
| `asc_subscriptions.py` | App Store | App Store Connect API, subscription groups and subscriptions |

Run them through `scripts/store_subscriptions.sh <play|ios> <list|sync> [options]`,
which sets up `store_products/.venv` and loads `fastlane/.env` for `ios`.

- `list` prints what the store has now.
- `sync` creates whatever is missing and updates names, descriptions and
  review notes. It is a **dry run** until you add `--apply`.
- `--only prime_monthly` limits a run to one product (repeatable).
- `--update-prices` changes a price that differs from the file. Without it a
  price difference is only reported. On Play the new price applies to new
  subscribers. On the App Store existing subscribers keep their price unless
  you also pass `--no-preserve-price`.

Prices are USD. Play converts them to every region; the App Store script picks
Apple's US price point and its equalized price points elsewhere. Apple only
sells fixed price points, so a price that isn't one fails with the nearest
valid ones.

Prime Lifetime is a one-time purchase (App Store non-consumable, Play one-time
product), which these scripts don't handle. Create it in the store consoles
with the values in `store_listing/ios/metadata.md` and
`store_listing/android/metadata.md`.

## Credentials

Nothing secret lives in this folder or in git.

**App Store Connect**: an API key with the Admin or App Manager role, the same
one `scripts/publish_ios.sh` uses, in `fastlane/.env` (gitignored):

```
ASC_KEY_ID=...
ASC_ISSUER_ID=...
ASC_KEY_PATH=~/keys/AuthKey_XXXX.p8
```

**Google Play**: a service account with the Google Play Android Developer API
enabled, invited in Play Console with at least **View app information** and
**Manage store presence**. Its JSON key goes in
`google_play/google-play-credentials.json` (gitignored), or set `PLAY_KEY_FILE`.

## Left to the store consoles

- **Play**: the app needs a payments profile and an uploaded build with the
  billing permission before Play accepts subscriptions.
- **App Store**: the first time, each subscription needs a review screenshot
  and must be submitted with an app version.
