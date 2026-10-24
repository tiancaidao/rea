# Google Play Console: Duplicate Sweep (Android)

Copy each field into Play Console. Anything in `<angle brackets>` is a
placeholder for you to fill.

## App details

| Field | Value |
| --- | --- |
| App name (30) | `Duplicate Sweep` (15). |
| Package name | `com.duplicates_cleaner.android` |
| Default language | English (United States) – en-US |
| App or game | App |
| Free or paid | Free (with in-app products) |
| Category | Tools |
| Tags (up to 5) | Storage cleaner, File manager, Device optimization, Photo management, Utilities |
| Contact email (required) | `<support@yourdomain.com>` |
| Website | `<https://yourdomain.com/duplicates-cleaner>` |
| Privacy policy (required) | `<https://yourdomain.com/duplicates-cleaner/privacy>` |

### Short description (80)

```
Find and delete duplicate photos, music, videos and documents to free up space.
```

(79 characters)

### Full description (4000)

```
Duplicate Sweep finds exact copies of your files and helps you remove them safely, so you get your storage back without losing anything you care about.

Photos copied into several folders, downloads saved twice, the same PDF in three folders: duplicates pile up quietly. Tap Smart Scan and Duplicate Sweep groups every set of identical files together, marks the original, and pre-selects only the extra copies.

★ MATCHED BY CONTENT, NOT BY NAME
• Files are compared by their content, so a photo in DCIM and its copy in Download are recognised as the same file, while two different files that share a name are left alone.
• An optional byte-by-byte check confirms every match before anything is offered for deletion.

★ SCAN EVERY FILE TYPE
• Images: jpg, png, gif, heif, tiff, bmp and more
• Audio: mp3, m4a, wav, flac, aac, opus and more
• Videos: mp4, mkv, avi, mov, 3gp, webm and more
• Documents: pdf, docx, xlsx, pptx, epub, zip, rar and more
• APK installer files (Prime)
• Your own custom file extensions (Prime)

★ YOU STAY IN CONTROL
• The original in every set is always kept and clearly labelled.
• Tap any file to open it before you clean.
• Pick exactly which copies to delete, or let auto-select do it for you.
• A confirmation step before deletion is on by default.

★ EVERY STORAGE LOCATION
• Internal storage
• SD card, USB OTG drives and parallel (dual) apps storage (Prime)
• Any custom folder you choose (Prime)

★ FINE-TUNE EVERY SCAN
• Match by content, or by name, name and size, or size alone (Prime)
• Find visually similar images (Prime)
• Skip files by size: tiny, small, medium or large (Prime)
• Sort and filter results by size, name, path or date (Prime)

★ PRIVATE BY DESIGN
Everything happens on your device. No account, no ads, no tracking, and your files are never uploaded anywhere.

★ FREE AND PRIME
The free version cleans up to 100 files and up to 500 MB per clean. Duplicate Sweep Prime removes those limits and unlocks every scan type and storage location. Choose a one-time Lifetime purchase or a monthly subscription that you can cancel at any time in Google Play.

Why "All files access"? Android only lets an app find duplicates across your folders, and delete the copies you choose, with this permission. Duplicate Sweep uses it only to scan and delete files on your device.
```

(about 2,450 characters)

### Release notes, en-US (500)

```
Welcome to Duplicate Sweep! Find and remove exact duplicate photos, music, videos and documents, and free up space in a few taps.
```

## Graphics

| Asset | File | Spec |
| --- | --- | --- |
| App icon | `icon-512.png` | 512 x 512 PNG, up to 1 MB |
| Feature graphic | `feature-graphic-1024x500.png` | 1024 x 500, no alpha |
| Phone screenshots | `screenshots/phone-1080x1920/01..06` | 1080 x 1920 (9:16); 2 to 8 required, 4+ at 1080 px qualify for promotion |
| 10-inch tablet screenshots | `screenshots/tablet-10in-1600x2560/01..06` | 1600 x 2560 |
| 7-inch tablet screenshots | Reuse the 10-inch set | Play accepts any size between 320 and 3840 px |
| Video | Optional YouTube URL | |

The launcher icon in the app (adaptive, pale blue background `#E4F0FE`) uses the
same artwork, so the store icon and the home-screen icon match.

## App content

### Privacy policy
`<https://yourdomain.com/duplicates-cleaner/privacy>` (host `../privacy-policy.md`).

### Ads
**No, my app does not contain ads.**

### App access
**All functionality is available without special access** (no login).

### Content rating (IARC questionnaire)
- Category: **All other app types** (utility / productivity).
- Violence, sexuality, language, controlled substances, gambling: **No** to all.
- Users can interact or exchange content: **No**.
- Shares user location: **No**.
- Allows purchases of digital goods: **Yes**.
- Unrestricted internet access / web browser: **No**.

Expected result: **Everyone / PEGI 3 / USK 0**, with the "In-App Purchases"
interactive element.

### Target audience and content
- Target age groups: **18 and over** (and 16–17 if you like). Do not pick
  under-13 groups, or the app falls under the Families policy.
- Appeals to children: **No**.

### News app
**No.**

### Data safety
| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | Not applicable (nothing is collected) |
| Do you provide a way for users to request that their data is deleted? | Not applicable |

Result shown on the listing: **No data collected, No data shared with third
parties.** Files are read and deleted on the device only; Export Log hands a
text file to the system share sheet only when the user taps it.

If you later add analytics, crash reporting, OneSignal or a billing SDK that
sends identifiers, revisit this form before that release.

### Government app, financial features, health
**No** to each.

## Sensitive permission: All files access (`MANAGE_EXTERNAL_STORAGE`)

Play reviews this permission. In **App content > Sensitive permissions >
All files access**, declare:

- Core use: **File management / storage cleaning**. Other choices may fit
  better at the time you submit; the core point is that the app must list and
  delete files across shared storage.
- Description:

```
Duplicate Sweep is a duplicate file finder. Its core feature is to scan the user's shared storage (all folders, SD card and USB drives) for files with identical content and delete the copies the user selects. MediaStore only exposes media files and cannot reach documents, archives, APKs or arbitrary extensions in every folder, and the Storage Access Framework would require the user to grant every folder one by one, which defeats a full-device duplicate scan. The permission is requested only when the user starts a scan, with an explanation screen, and files never leave the device.
```

- Video: Play usually asks for a short screen recording showing the feature
  that needs the permission. Record: open the app, tap Smart Scan, grant All
  files access from the prompt, show the grouped results and delete one copy.

## In-app products

Product IDs must match what the billing code queries. The original app used
`dc_prime_one_time_purchase` and `dc_prime_benefits`; pick your own names.

| | One-time product | Subscription |
| --- | --- | --- |
| Product ID | `prime_lifetime` | `prime_monthly` (base plan `monthly`, auto-renewing, 1 month) |
| Name | Prime Lifetime | Prime Monthly |
| Description | Unlimited cleaning and every scan, forever | Unlimited cleaning and every scan, monthly |
| Price | USD 9.99 | USD 1.99 / month |
| Benefits (subscription, up to 4) | | Unlimited files per clean · SD card, USB and custom folders · Similar images and APK scans · Sort and select filters |

## Store settings: pre-launch checklist
- Target API level: Play currently requires targeting the latest Android API
  level within a year of its release; check `targetSdk` in
  `android/app/build.gradle.kts` (Flutter's default tracks the latest).
- Upload an Android App Bundle: `flutter build appbundle --release`, signed
  with your upload key and Play App Signing enabled.
- New personal developer accounts must run a closed test with at least 12
  testers for 14 days before production access.
