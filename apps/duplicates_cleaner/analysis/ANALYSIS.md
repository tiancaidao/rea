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

**Same appearance** (`FilesScanner.GroupByPhaseOne`): per-image pHash (DCT,
64-bit) plus region features (centre average, four corner deltas, spiral and
centre deltas). Two images match when the pHash Hamming distance is at most 12
and at least 5 of the 8 checks agree; matches are joined by breadth-first
grouping.

**Size exclusion** (`FilesScanner.FileCanBeProcessed`): files under 8 KB are
always skipped. Tiny excludes up to 1 MB, Small 1 to 50 MB, Medium 50 to
250 MB, Large 250 MB and above.

**Storage options** (`StorageSelection`): internal, SD card, custom folder,
parallel storage, internal + SD card, USB (Android 11+). Uses
`MANAGE_EXTERNAL_STORAGE`; SD card and USB deletion goes through
`DocumentFile` tree URIs.

**Selection** (`AggregateResults`): the first file of each group is the main
file and stays unchecked; others are checked when Auto Select is on. Select
filters: Select all, Unselect all, Select duplicates.

**Sort** (`IDuplicatesGroupingService`): size, name length, name alphabetical,
path, date created; ascending or descending.

**Free tier limits** (`Constants`): at most 100 files per delete operation,
and files of 500 MB (524,288,000 bytes) and above need premium. Premium
products: `dc_prime_benefits` (subscription) and `dc_prime_one_time_purchase`.
Premium also unlocks SD card, similar images, USB, parallel and custom folder
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
| `SkiaImageMathOperations.GetPHash`         | `lib/services/image_hash.dart` (pHash only, see differences) |
| `CommonPageData` / `SettingsData`          | `lib/services/settings_store.dart` (shared_preferences) |
| `GoogleBillingService`, licence service    | `lib/services/premium_service.dart` (stub) |
| `ScannerPageActivity` selection and delete | `lib/services/results_controller.dart`, `lib/screens/scanner_screen.dart` |
| Activities                                 | `lib/screens/*` |

### Deliberate differences

- **Byte-for-byte confirmation.** Partial fingerprint matches are confirmed by
  comparing whole files before they are offered for deletion, so two files that
  only share their sampled regions are never grouped.
- **Similar images** use the pHash with the same Hamming threshold of 12, but
  not the extra region checks. The pure-Dart decoder covers JPEG, PNG, GIF,
  TIFF and BMP; HEIF, EPS and RAW are skipped in this mode.
- **Billing and licensing** are not wired. `PremiumService` keeps the same
  gates and can be unlocked from the upgrade dialog in debug builds.
- **Left out**: PairIP, OneSignal, sideload licensing, cross-promotion links,
  log export, the rating prompt, and the SQLite results cache.
- **SD card / USB deletion** uses direct file deletion, which Android may
  refuse on removable volumes without a Storage Access Framework grant. Those
  files are reported as failed instead of silently skipped.
- **iOS** has no shared file system, so "internal" scans the app's Documents
  folder (visible in the Files app) and "custom folder" uses the system
  folder picker. The original is Android only.
