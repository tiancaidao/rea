# Duplicate Sweep: store listing kit

Everything needed to fill in App Store Connect and Google Play Console.

| Folder / file | What it holds |
| --- | --- |
| `ios/metadata.md` | Name, subtitle, keywords, description, promo text, What's New, categories, URLs, App Privacy answers, age rating answers, in-app purchases, review notes, export compliance |
| `ios/app-icon-1024.png` | 1024 x 1024 opaque App Store icon |
| `ios/screenshots/iphone-6.9in-1320x2868/` | Required iPhone set (6 images) |
| `ios/screenshots/iphone-6.5in-1284x2778/` | Optional iPhone 6.5" set |
| `ios/screenshots/ipad-13in-2064x2752/` | iPad set, required while the app supports iPad |
| `android/metadata.md` | Title, short and full description, release notes, category, Data safety, content rating, target audience, All files access declaration, in-app products |
| `android/icon-512.png`, `android/feature-graphic-1024x500.png` | Play icon and feature graphic |
| `android/screenshots/phone-1080x1920/`, `android/screenshots/tablet-10in-1600x2560/` | Play phone and tablet sets |
| `privacy-policy.md` | Privacy policy text to host at your privacy URL |
| `preview-iphone.png` | All six iPhone screenshots side by side |

## Screenshot story

1. **Free up space in one tap**: home screen
2. **Find exact duplicate photos**: results of a real scan, original kept
3. **Scan every file type**: categories
4. **The original is always kept**: safety
5. **Tune every scan your way**: settings
6. **Go Prime for no limits**: paywall

The screens are the real Flutter app rendered by
`apps/duplicates_cleaner/tool/store_assets_test.dart`; the results screen
comes from an actual scan of sample photos. Text uses Roboto because Apple's
SF font can't be bundled, and captions use Plus Jakarta Sans (OFL). To
regenerate after UI changes, see the header of that file.

## Fix before you submit

These are in the app, not the listing, and each one would get a review
rejection or a bad first impression:

1. **Billing is not wired.** `PremiumService` is a stub, so the paywall can't
   actually sell Prime. Apple (guideline 2.1 / 3.1.1) and Google both reject a
   paywall that doesn't complete a purchase. Wire StoreKit / Play Billing
   (for example `in_app_purchase` or RevenueCat) with the product IDs in the
   metadata files, plus a working Restore.
2. **Bundle ID and package name are `com.example...`.** Both stores refuse
   these. Change them before creating the store records.
3. **iPhone photos are HEIC, and HEIC isn't in the image extensions**, so an
   Images scan on iOS misses most camera photos. Add `heic` (and `dng`).
4. **APK scan shows on iOS.** It means nothing there; hide the APK tile on iOS.
5. **iPad layout isn't adapted.** On a 13" iPad the phone layout stretches
   (see the iPad screenshots). Either set the iOS target to iPhone only
   (`TARGETED_DEVICE_FAMILY = 1`), which drops the iPad screenshot
   requirement, or add a tablet layout.
6. **Name.** The store name is now "Duplicate Sweep", because "Duplicates Cleaner" was taken on the App Store. The app's display name, captions and listing text all match it.
7. Add `ITSAppUsesNonExemptEncryption = NO` to `Info.plist`.
8. Host the privacy policy and a support page, then fill the URL
   placeholders.
