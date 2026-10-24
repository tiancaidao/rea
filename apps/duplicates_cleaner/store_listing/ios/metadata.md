# App Store Connect: Duplicate Sweep (iOS)

Copy each field into App Store Connect. Character counts are given against
Apple's limits. Anything in `<angle brackets>` is a placeholder for you to fill.

## App information

| Field | Value |
| --- | --- |
| Name (30) | `Duplicate Sweep` (15) |
| Subtitle (30) | `Find & delete duplicate files` (29) |
| Bundle ID | `com.duplicates-cleaner.ios` |
| SKU | `duplicates-cleaner-ios-001` |
| Primary language | English (U.S.) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content rights | Does not contain, show or access third-party content |
| Copyright | `2026 <Your name or company>` |
| Version | 1.0.0 |

## Version text

### Promotional text (170)

Can be changed at any time without a new build.

```
Free up storage in minutes. Scan your folders for exact duplicate photos, music, videos and documents, review every match, and keep the original with one tap.
```

(158 characters)

### Keywords (100)

Comma separated, no spaces. Words already in the name or subtitle are left out
because Apple indexes those anyway.

```
storage,space,cleanup,copies,dedupe,photo,music,video,pdf,similar,organizer,remove,folder,cleaner
```

(97 characters)

### Description (4000)

```
Duplicate Sweep finds exact copies of your files and helps you remove them safely, so you get your storage back without losing anything you care about.

Downloads saved twice, photos copied into several folders, the same PDF in three places: duplicates pile up quietly. Pick a folder, tap Smart Scan, and Duplicate Sweep groups every set of identical files together, marks the original, and pre-selects only the extra copies.

MATCHED BY CONTENT, NOT BY NAME
• Files are compared by their content, so "IMG_2041.jpg" and "IMG_2041 (1).jpg" are recognised as the same photo, while two different files that happen to share a name are left alone.
• An optional byte-by-byte check confirms every match before anything is offered for deletion.

SCAN EVERY FILE TYPE
• Photos: jpg, png, gif, heif, tiff, bmp and more
• Music and audio: mp3, m4a, wav, flac, aac and more
• Videos: mp4, mov, mkv, avi and more
• Documents: pdf, docx, xlsx, pptx, epub, zip and more
• Your own file extensions (Prime)

YOU STAY IN CONTROL
• The original in every set is always kept and clearly labelled.
• Tap any file to preview it before you clean.
• Choose exactly which copies to delete, or let auto-select do it for you.
• A confirmation step before deletion is on by default.

WHERE IT SCANS
Duplicate Sweep scans the folders you choose in the Files app, including On My iPhone, iCloud Drive and connected drives, plus its own Duplicate Sweep folder. It does not read your Photos library.

FINE-TUNE EVERY SCAN
• Match by content, or by name, name and size, or size alone (Prime)
• Find visually similar images (Prime)
• Skip files by size: tiny, small, medium or large (Prime)
• Sort and filter results by size, name, path or date (Prime)

PRIVATE BY DESIGN
Everything happens on your device. No account, no ads, no tracking, and your files never leave your phone.

FREE AND PRIME
The free version cleans up to 100 files and up to 500 MB per clean. Duplicate Sweep Prime removes those limits and unlocks every scan type, similar-image matching, custom extensions, and the sort and select filters.

• Prime Lifetime: a one-time purchase.
• Prime Monthly: an auto-renewing monthly subscription.

Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the period ends. You can manage or cancel the subscription in your App Store account settings.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: <https://yourdomain.com/duplicates-cleaner/privacy>
```

(about 2,600 characters)

### What's New in This Version (4000)

```
Welcome to Duplicate Sweep! Find and remove exact duplicate photos, music, videos and documents, and free up space in a few taps.
```

## URLs

| Field | Value |
| --- | --- |
| Support URL (required) | `<https://yourdomain.com/duplicates-cleaner/support>` |
| Marketing URL (optional) | `<https://yourdomain.com/duplicates-cleaner>` |
| Privacy Policy URL (required) | `<https://yourdomain.com/duplicates-cleaner/privacy>` (host the text in `../privacy-policy.md`) |
| Terms of Use (EULA) | Apple's standard EULA, linked in the description |

## Images

| Slot | File | Size |
| --- | --- | --- |
| iPhone 6.9" display (required) | `screenshots/iphone-6.9in-1320x2868/01..06` | 1320 x 2868 |
| iPhone 6.5" display | `screenshots/iphone-6.5in-1284x2778/01..06` | 1284 x 2778 |
| iPad 13" display (required while the app supports iPad) | `screenshots/ipad-13in-2064x2752/01..06` | 2064 x 2752 |
| App icon | `app-icon-1024.png` | 1024 x 1024, opaque |

Upload the screenshots in order 01 to 06; the first three show in search
results. All PNGs are RGB with no alpha channel, as Apple requires. Since
2024 Apple scales the 6.9" set down for smaller iPhones, so the 6.5" set is
optional; it is included in case you want to tune it separately.

The app icon in App Store Connect comes from the build. The same icon is in
the repo's `AppIcon.appiconset`, so the next build carries it.

## App Privacy ("nutrition label")

Answer **"No, we do not collect data from this app."** The result is
**Data Not Collected**.

Why this is accurate: the app has no analytics, crash reporting, ads, account
or server. Scans, results and the log stay on the device. Export Log and the
rating prompt only run when the user taps them, and the share sheet and
StoreKit review prompt are Apple's.

If you later add OneSignal, Firebase, RevenueCat or similar, update this
section before you ship that build.

## Age rating

Answer **None** or **No** to every question in the questionnaire:

| Question group | Answer |
| --- | --- |
| Violence, sexual content, nudity, profanity, horror, drugs, alcohol, tobacco, gambling themes, mature themes | None |
| Medical or wellness topics | No |
| Simulated gambling, contests, loot boxes | No |
| Unrestricted web access | No |
| User-generated content, messaging or chat | No |
| Advertising | No |
| Parental controls / age assurance | No |

Result: **4+**.

## Pricing and in-app purchases

App price: **Free**, with in-app purchases. Prices match the paywall.

| | Prime Lifetime | Prime Monthly |
| --- | --- | --- |
| Type | Non-consumable | Auto-renewable subscription |
| Reference name | Prime Lifetime | Prime Monthly |
| Product ID | `prime_lifetime` | `prime_monthly` |
| Subscription group | | Duplicate Sweep Prime |
| Duration | | 1 month |
| Price | USD 9.99 | USD 1.99 / month |
| Display name (30) | `Prime Lifetime` | `Prime Monthly` |
| Description (45) | `Unlimited cleaning and every scan, forever` (42) | `Unlimited cleaning and every scan, monthly` (42) |
| Review screenshot | `screenshots/iphone-6.9in-1320x2868/06_prime.png` | same |

Subscription group display name: `Duplicate Sweep Prime`.

## App Review information

Sign-in required: **No**.

Notes for the reviewer:

```
Duplicate Sweep finds exact duplicate files in folders the user chooses. No account is needed.

To test quickly:
1. Open the Files app > On My iPhone > Duplicate Sweep, and copy any photo or PDF into that folder two or three times (Files > long-press > Duplicate).
2. Open Duplicate Sweep, skip or finish the intro, and tap Smart Scan (or Images / Docs).
3. The copies are grouped; the original is marked "Original" and kept. Tap Clean Now to delete the selected copies.

Settings > Scan Location > Custom folder lets the user pick any folder in Files, including iCloud Drive.

The free version cleans up to 100 files and 500 MB per clean. Prime (Lifetime non-consumable or Monthly subscription) removes the limits; Restore is on the paywall.
```

Contact: `<first and last name>`, `<phone>`, `<email>`.

## Export compliance

The app uses no encryption beyond what iOS provides. Add this to
`ios/Runner/Info.plist` so App Store Connect stops asking on every build:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
