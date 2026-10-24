# Store subscriptions

`subscriptions.json` defines the app's Prime products: the auto-renewing
Prime Monthly subscription, and Prime Lifetime, a one-time purchase. Three
scripts make the stores and RevenueCat match it:

| Script | Where | API |
|---|---|---|
| `play_subscriptions.py` | Google Play | Play Developer API, `monetization.subscriptions` |
| `asc_subscriptions.py` | App Store | App Store Connect API, subscription groups and subscriptions |
| `revenuecat_products.py` | RevenueCat | REST API v2: products, entitlement, offering and packages |

Run them through `scripts/store_subscriptions.sh <play|ios|revenuecat> <list|sync> [options]`,
which sets up `store_products/.venv` and loads `fastlane/.env` for `ios` and
`revenuecat`.

## How the app buys Prime

`lib/services/premium_service.dart` uses RevenueCat (`purchases_flutter`).
Prime is the `prime` entitlement. The current offering (`default`) has a
`$rc_monthly` package holding `prime_monthly` and a `$rc_lifetime` package
holding `prime_lifetime`, each with its App Store and Play product.
`revenuecat_products.py sync` adds every product, attaches them to the
entitlement, creates the packages and makes the offering current. It never
deletes.

The app reads the RevenueCat public SDK keys from `--dart-define`
(`REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`). `scripts/publish_ios.sh` and
`scripts/publish_android.sh` pass them from `fastlane/.env` and refuse to build
a release without one, unless `ALLOW_NO_BILLING=1`.

Order for a new setup:

1. In RevenueCat, create the project and add the App Store app (bundle id,
   in-app purchase key) and the Play Store app (package, service account).
2. Create the products in each store: `store_subscriptions.sh ios sync --apply`,
   `store_subscriptions.sh play sync --apply`, and Prime Lifetime in each
   console.
3. `store_subscriptions.sh revenuecat sync --apply`.
4. Put the public SDK keys in `fastlane/.env` and publish.

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

**RevenueCat**: a v2 secret API key with project configuration read and write
(Project settings > API keys) and the project id from the dashboard URL, also in
`fastlane/.env`:

```
REVENUECAT_API_KEY=sk_...
REVENUECAT_PROJECT_ID=proj...
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
