# Duplicates Cleaner 4.2.4: reverse-engineering notes

Target: Google Play `com.kaerosduplicatescleaner`, version 4.2.4 (version code
159), supplied as an APKCube `.apks` split bundle.

| Artifact                           | SHA-256                                                            |
| ---------------------------------- | ------------------------------------------------------------------ |
| `Duplicates-Cleaner_4.2.4_apkcube.apks` | `bb7f34c453fa0757ba2336ab8baf2fa04a904f6f3274da9d95ddf1104b117162` |
| `base.apk`                         | `a76df1790570d3abd67239e73b662329cc5fba9e03d5c425640d5faa6eb2d200` |
| `split_config.arm64_v8a.apk`       | `30bf2eac5941180c085717c50d977fedd7caec2468b91dfc795d687dd7d3d237` |
| `DCAndroidPort.dll` (app logic)    | `b777ed5fb6ce3c3e91edf881d11368cf5cfbdf261da7ac87f66e806a007c3a61` |
| `DCAndroid.Data.dll` (data model)  | `be7218c17c47b1df7c7a326fa939fb5b996f07b03be35538ffe4ffc902db7359` |

## How it was analyzed

1. **Unpack the bundle.** The `.apks` is a ZIP holding `base.apk` plus ABI,
   language and density splits.
2. **Identify the runtime.** The arm64 split carries `libmonosgen-2.0.so`,
   `libmonodroid.so`, `libxamarin-app.so`, `libaot-*.dll.so` and
   `libassemblies.arm64-v8a.blob.so`. This is a **.NET for Android (Xamarin)**
   app, so `classes.dex` only holds generated Java callable wrappers and the
   real logic lives in managed assemblies.
3. **Extract the assemblies.** The `payload` ELF section of
   `libassemblies.arm64-v8a.blob.so` is an `XABA` v2 assembly store (113
   entries, LZ4 `XALZ` compressed). `tools/extract_assembly_store.py` unpacks
   them to plain PE/CLI DLLs.
4. **REA managed-code analysis.**
   `rea inspect-managed-artifact` classifies `DCAndroidPort.dll` as
   `modern-dotnet`, IL-only, AnyCPU. `rea inspect-managed-members` returned
   complete coverage: 217 types, 1,311 methods, 7,143 call edges and 4,199
   field accesses. That inventory gave the class map below.
5. **CIL with literals.** REA's member view keeps opcodes and tokens but not
   resolved string literals, so `tools/cil_dump.py` (dnfile + dncil) prints each
   method body with `ldstr` values and member names, and constants were read
   from the metadata `Constant` table.
6. **REA resource analysis.** `rea decode-android-resources` (Apktool 2.10.0)
   decoded the manifest and 393 default strings; a full `apktool d --no-src`
   gave layouts, arrays, colours and drawables.

Not done: no dynamic analysis (no device or emulator), and AOT native bodies
(`libaot-*.so`) were not examined, since the IL is present and authoritative.

## Architecture

- `DCAndroidPort` (UI, services) and `DCAndroid.Data` (EF Core + SQLite model
  `DuplicateItemModel`).
- Autofac `ServicesContainer` wires: `FileStorageContextService` (EF Core
  SQLite cache of results), `GoogleBillingService`, `SkiaImageIOService`,
  `SkiaImageMathOperations`, `SkiaImageOperations`.
- Serilog file logging to `<external files>/logs/KaerosDCLog.txt`
  (Settings → Export Log).
- Protected with PairIP (`com.pairip.application.Application`), OneSignal push
  receiver, Google Play Billing, plus a sideload licence API
  (`kaeroscorps.com/licensing-api/activate.php`, 7 day offline grace).

## Screens (activities)

| Activity                    | Role |
| --------------------------- | ---- |
| `DemoScreenActivity`        | Launcher splash; initialises services and billing, then routes to the tutorial (first run) or home. |
| `TutorialActivity`          | ViewPager2 walkthrough: Welcome, Home Page, Duplicate Selection, View Files, Settings, Clean Genuine Duplicates, Stay Clean, Premium Version, Support Assistance. |
| `HomeScreenActivity`        | Title ("Duplicates Cleaner" / "Duplicates Cleaner Prime") and a grid: Scan Images, Scan Audio, Scan Videos, Scan Docs, Scan APK, Scan Custom Files, Settings, About. Shows a "Free Version Limits" dialog on first launch. |
| `ScannerPageActivity`       | Permission check, storage resolution, scan with a circular percentage indicator ("Analyzing..." / "Comparing..."), grouped results list, Select and Sort filter buttons, "CAN BE DELETED (size)" button, deletion with confirmation, rating prompt. |
| `SettingsActivity`          | Scan Location, Scan Type, File Size Exclusion, Auto Select Duplicates, Prompt Before File Deletion, Custom Extensions, Export Log. |
| `AboutActivity`             | Version, upgrade, user guide, support, blog/news and cross-promotion links. |
| `LicenseActivationActivity` | E-mail + activation code for sideloaded installs. |

## Behaviour recovered from code

**File categories** (`StaticDataStore`):
images `jpg jpeg png gif tiff tif bmp heif eps raw`; audio
`mp3 wav wma m4a flac aac amr opus asf asx midi`; video
`mp4 avi vob mkv flv 3gp mov wmv webm`; docs
`pdf doc docx rtf xls xlsx ppt pptx mobi epub rar zip txt cbr cbz fb2 ttf`;
APK `apk`; custom extensions validated with `^,?[A-Za-z0-9]+(,[A-Za-z0-9]+)*$`.

**Scan algorithms** (`ScanAlgorithmType`): same content (default), same name,
same name and size, same size, same appearance (images).

**Same content fingerprint** (`FileCheck.GetXhash`): file size plus XXH32
(`KHash`, standard primes) of 4096 bytes at offset 2048 and XXH32 of the last
2048 bytes. Candidates are first grouped by size. This is a sampled hash, not a
full-content comparison, despite the "100% content match" copy.

**Same appearance** (`FilesScanner.ProcessImageSimilarity`, `GroupByPhaseOne`,
`GroupFinal`, `GroupByHeight`). Per image, the original computes:

- `CropDelta`: average colour of the centre cell of a 3x3 grid.
- A grayscale copy scaled to 100 px wide (aspect ratio kept). Its height is
  stored as `Height`, so it acts as an aspect-ratio key.
- From the grayscale copy: average brightness of five regions (`TL`, `TR`,
  `BL`, `BR`, `CentreAVG`); a grid-of-points RMS value (`CentreDelta`); a DCT
  of brightness sampled along an Archimedean spiral (`ArchSpiroDelta`); and a
  64-bit pHash (32x32 DCT, top-left 8x8).

Matching runs in two passes, and only images with the same `Height` (same
aspect ratio) are ever compared:

1. Two images are linked when **all 8 checks pass**: pHash Hamming distance
   at most 12, each of the five region averages within 10, `CentreDelta`
   within 10, and `ArchSpiroDelta` within 5. They are also linked when the
   pHash distance alone is **at most 5**. Linked images are joined into groups
   by breadth-first search.
2. Images left on their own after pass 1 get a second chance. They are linked
   when the normalised chromaticity distance between their centre colours is
   at most 2.0 **and** the pHash distance is at most 13.

**Size exclusion** (`FilesScanner.FileCanBeProcessed`): with Exclude None,
files under 8 KB are skipped; other settings use their range alone. Tiny excludes up to 1 MB, Small 1 to 50 MB, Medium 50 to
250 MB, Large 250 MB and above.

**Storage options** (`StorageSelection`): internal, SD card, custom folder,
parallel storage, internal + SD card, USB (Android 11+). Uses
`MANAGE_EXTERNAL_STORAGE`; SD card and USB deletion goes through
`DocumentFile` tree URIs.

**Selection** (`AggregateResults`): the first file of each group is the main
file and stays unchecked; others are checked when Auto Select is on. Select
filters: Select all, Unselect all, Select duplicates.

**Sort** (`IDuplicatesGroupingService`): size, name length, name alphabetical,
path, date created; ascending or descending (New / Old for date created). Each
`GetSortedGroupsBy*` orders *every file* by the key, then regroups, and
`AggregateResults` marks the first file of each group as the main file, so the
sort also decides which copy is kept (Date created - Old keeps the oldest). The
selection is reset to the Auto Select setting after a sort. "Path" orders by
the path's *length*, not alphabetically.

**Scan pipeline** (`ScannerPageActivity.ScanFiles`): same content and same size
both run `ProcessFiles` (size candidates, then `GetXhash`); a file whose hash is
0, i.e. under 2048 bytes, is never stored. Same name and same name and size run
`ProcessFilesNonSameContent`. Same appearance runs `ProcessSimilarImageFiles`
for image scans only. An image scan of internal storage lists files from the
MediaStore index (`_data LIKE '/storage/emulated/%'`, no extension filter);
every other scan walks folders breadth first with a queue, files before
subfolders, hidden files included. Custom Files with no extensions set scans
nothing.

**Settings** (`SettingsActivity`): Android 10 and below only offer Internal, SD
Card, Custom Folder and Parallel. Choosing SD Card or Internal + SD Card with no
card mounted resets to internal storage and shows "SD Card Not Found!". The
similar image warning appears when Same Appearance is chosen there.

**Results**: tapping a file opens it in another app, or shows "File Launch
Failed!" naming the file type. Deletion reports a percentage and passes every
deleted internal-storage file to `MediaScannerConnection.scanFile`.

**Free tier limits** (`DeleteSelectedDuplicates`): at most 100 files per
delete operation, and a selection totalling 500 MB (524,288,000 bytes) or more
needs premium. Premium
products: `dc_prime_benefits` (subscription) and `dc_prime_one_time_purchase`.
Premium also unlocks the APK and Custom Files scans, SD card, similar images, USB, parallel and custom folder
scans, size exclusion, non-content algorithms, custom extensions, and sort and
select filters.

**Look and feel**: primary `#FFD046`, primary dark `#FFBD21`, accent
`#3498DB`, background `#FDF8F2`, rounded panels (25 dp) and cards (15 dp),
60 dp thumbnails.

## Flutter mapping

| Original                                   | Flutter recreation |
| ------------------------------------------ | ------------------ |
| `KHash`                                    | `lib/core/xxhash32.dart` |
| `FileCheck.GetXhash`                       | `lib/services/content_fingerprint.dart` |
| `FilesScanner` + grouping services         | `lib/services/scan_engine.dart`, run on an isolate by `background_scanner.dart` |
| `SkiaImageMathOperations`, `SkiaImageOperations`, `GroupFinal` | `lib/services/image_similarity.dart` (all nine features, both passes) |
| `CommonPageData` / `SettingsData`          | `lib/services/settings_store.dart` (shared_preferences) |
| `GoogleBillingService`, licence service    | `lib/services/premium_service.dart` (stub) |
| `ScannerPageActivity` selection and delete | `lib/services/results_controller.dart`, `lib/screens/scanner_screen.dart` |
| Activities                                 | `lib/screens/*` |

### Deliberate differences

- **Same content** uses the original hash and groups by it alone. An extra
  step, on by default (Settings → Confirm Same Content Byte by Byte), splits
  each group by real byte equality, so a hash collision never offers a
  different file for deletion. Files under 2 KB, which the original's hash maps
  to 0 and never stores, are skipped by same content and same size scans.
- **Same name** finds candidates by lower-cased name and then groups by the
  exact name, as the original does. **Name and size** uses the original
  `NSHash` key (lower-cased name followed by the size).
- **Similar images** port all nine features, both passes, the aspect-ratio
  buckets and .NET's half-to-even rounding. Differences: images are decoded
  and resized by the pure-Dart `image` package rather than Skia, so values can
  differ by a level or two; HEIF, EPS and RAW are skipped; and groups of one
  image, which the original can emit from pass 2, are dropped.
- **Billing and licensing** are not wired. `PremiumService` keeps the same
  gates and can be unlocked from the upgrade dialog in debug builds.
- **Left out**: PairIP, OneSignal, sideload licensing, cross-promotion and
  support links, and the SQLite results cache.
- **SD card / USB deletion** tries a direct delete first and, when Android
  refuses it, asks once per volume for folder access through the Storage
  Access Framework (`MainActivity.kt`), like the original's `DocumentFile`
  path. Files that still can't be deleted are reported as failed.
- **Export Log** shares a plain-text log of scans and deletions; the rating
  prompt follows `ProcessDeletionThreshold` (every second successful delete)
  and uses the platform's in-app review sheet.
- **iOS** has no shared file system, so "internal" scans the app's Documents
  folder (visible in the Files app) and "custom folder" uses the system
  folder picker. The original is Android only.

## Gap analysis against the port

A second pass compared the CIL of `ScannerPageActivity`, `FilesScanner`,
`FileUtility`, the five `DuplicatesGrouping*Service` classes and
`SettingsActivity` with the Flutter code, area by area.

| Area | Original | Port before | Port now |
| ---- | -------- | ----------- | -------- |
| File categories, custom extension pattern | `StaticDataStore` | Same | Same |
| Size exclusion ranges, 8 KB floor | `FileCanBeProcessed` | Same | Same |
| Same content fingerprint | `GetXhash`, hash 0 never stored | Same hash, files under 2 KB grouped by hash 0 | Files under 2 KB skipped |
| Same size | Content pipeline, grouped by size | Grouped by size, any size | Files under 2 KB skipped |
| Same name / name and size | `ProcessFileByName`, `NSHash` | Same | Same |
| Same appearance | Nine features, two passes | Same | Same |
| Walk order | Breadth first queue, hidden files included | Depth first stack, hidden files skipped | Breadth first, hidden included |
| Internal storage image scan | MediaStore index | Folder walk | MediaStore index (Android) |
| Main (kept) file | First stored row per group | Same | Same |
| Sort | Reorders files, regroups, first file is kept, selection reset | Reordered groups only | Same as original |
| Path sort key | Path length | Path, alphabetical | Path length |
| Select filters | All, none, duplicates; Prime | Same | Same |
| Free limits | More than 100 files, or 500 MB or more | Same | Same |
| Prime gates | APK, Custom, storage, algorithms, exclusion, filters | Same | Same |
| Scan locations on Android 10 and below | Four options | All six | Four options |
| SD card missing when chosen in Settings | Reset to internal, dialog | Error at scan time | Reset to internal, dialog |
| Similar image warning | When chosen in Settings | At scan start | When chosen in Settings |
| Open file with no app | "File Launch Failed!" dialog | Nothing shown | Dialog |
| After deleting | Media scanner told, progress shown | Not told, spinner | Media scanner told, percentage |

Left as they were, on purpose: same appearance chosen for a non-image scan
falls back to same content (the original groups those files by an unset
`SimHash`, which puts them all in one set); groups left with one file after a
delete are hidden; the Free Version Limits dialog is replaced by the paywall
that follows onboarding, which lists the same limits.
