# Duplicates Cleaner (Flutter)

A Flutter recreation of the Android app *Duplicates Cleaner* 4.2.4
(`com.kaerosduplicatescleaner`) for Android and iOS. It was rebuilt from a
static analysis of the original APK with REA; the findings, hashes and the
deliberate differences are in [analysis/ANALYSIS.md](analysis/ANALYSIS.md).

## Features

- Scan images, audio, video, documents, APKs or custom extensions.
- Five scan types: same content (default), same name, same name and size,
  same size, and same appearance for images.
- Scan locations: internal storage, SD card, custom folder, parallel storage,
  internal + SD card, USB (Android). Internal Documents and a picked folder on
  iOS.
- File size exclusion, auto-selection of duplicates, prompt before deletion.
- Grouped results with thumbnails, tap to open, select and sort filters,
  delete selected with the reclaimed size shown.
- The original free tier limits and premium gates, with billing left as a stub.

Scanning runs on a background isolate. Same-content matches use the original
app's sampled XXH32 fingerprint and are then confirmed byte for byte.

## Run

```sh
flutter pub get
flutter run            # pick an Android or iOS device
flutter test           # engine, hashing and selection tests
```

On Android 11+ the app asks for **All files access**. On iOS, put files in the
app's folder from the Files app, or choose *Scan Custom Folder* in Settings.

## Before shipping

- Change `applicationId` / bundle identifier (`com.example.duplicates_cleaner`).
- Wire `lib/services/premium_service.dart` to `in_app_purchase` with your own
  products. Debug builds can unlock premium from the upgrade dialog.
- Replace the placeholder Material icons and launcher icon with your own art.
- SD card and USB deletion may need a Storage Access Framework grant.

## Analysis tools

`analysis/tools/extract_assembly_store.py` unpacks the `XABA` assembly store
from `libassemblies.<abi>.blob.so` (needs `pip install lz4`).
`analysis/tools/cil_dump.py` prints CIL with resolved strings and member names
(needs `pip install dnfile dncil`).
