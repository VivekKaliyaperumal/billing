# Thyantra Billing (Android)

Offline point-of-sale for small shops: billing, stock, customer credit, sales reports. Published by Thyantra Technologies. No backend: all data stays on the phone.

- Package: `com.thyantra.billing`
- Play Store listing, Data safety answers and graphics: [docs/play-store/LISTING.md](docs/play-store/LISTING.md)
- Privacy policy: https://thyantra.com/billing-privacy-policy (page lives in the `thyantra` website repo)

## Run and test

```sh
flutter pub get
flutter run                                   # device or emulator
flutter analyze                               # strict lints; must be clean
flutter test                                  # logic suite on the desktop VM (in-memory SQLite)
flutter test integration_test -d <device-id>  # same suite on Android with real SQLite
```

On machines where Windows Application Control blocks `flutter_tester.exe`, run the integration command against an emulator instead; it covers the same 21 tests.

## Release

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create_upload_keystore.ps1   # once
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1            # every release
```

- The keystore script asks for the password (never stored in the repo), writes the keystore to `%USERPROFILE%\.thyantra-keys\` and `android/key.properties` (git-ignored). **Back up both.**
- Release builds refuse to run without `key.properties`; nothing is ever debug-signed.
- The build script runs analyze + tests, then builds an obfuscated, R8-minified app bundle. Keep `build/symbols` per release for crash stack traces.
- Bump `version:` in `pubspec.yaml` (the `+N` build number) for every upload.

## Architecture

| Layer | Files | Notes |
|---|---|---|
| Storage | `lib/data/app_database.dart` | SQLite (sqflite). Multi-row operations run in one transaction; stock and balances are guarded in SQL so they can't go negative. |
| State | `lib/providers/` | In-memory mirrors of the database. They change only **after** a write succeeds. |
| Use cases | `lib/services/checkout_service.dart`, `backup_service.dart` | Checkout: reconcile cart with inventory, resolve customer, save sale, stock and credit atomically. Backup: JSON export/restore with strict validation of the (untrusted) file. |
| UI | `lib/screens/`, `lib/widgets/`, `lib/shell/` | Thyantra theme (`lib/theme/`), bundled Inter and Sora fonts, 48dp touch targets, screen-reader labels. |
| Helpers | `lib/utils/` | `money.dart` (integer minor units), `validation.dart`, `csv_export.dart` (RFC 4180 + formula-injection safe), `receipt_pdf.dart`. |

### Data rules

- **Money** is always an `int` in minor units (paise/cents), so totals never drift. User input goes through `parseAmount`, which rejects NaN, exponents, negatives, more than 2 decimals and amounts over ₹1 crore.
- **Phone numbers** are normalised (spaces/dashes removed) and unique per customer.
- **Customers** with a pending balance can't be deleted; payments can't exceed the balance.
- **Product images** must be `https://`. Cleartext traffic is disabled in the manifest.
- **Legacy data** from the earlier SharedPreferences storage is imported once on first launch, cleaned up (negative stock clamped, duplicate phones merged), then removed. Unreadable records are skipped and kept under `<key>_corrupt_<timestamp>`.
- **Settings and theme** remain in SharedPreferences (`shop_settings`, `shop-ui-theme`).

### Privacy and network

No analytics, ads, crash reporting or accounts. The only network use is loading product images from URLs the user enters. Fonts are bundled, so nothing is fetched at runtime.

## Branding

Icons are generated from `assets/branding/` (logo from the Thyantra website): `dart run flutter_launcher_icons`. Colours are in `lib/theme/app_theme.dart` (`Brand`).
