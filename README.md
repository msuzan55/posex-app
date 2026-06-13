# PosEx Mobile App (Flutter)

Native Android/iOS shell for [PosEx](https://posex.lk) — Sri Lankan retail POS.

## Stack

- Flutter (stable)
- Package: `lk.posex.posex_app`
- API base: `https://posex.lk` (see `lib/config/api_config.dart`)

## Project layout

```
posex-app/
├── lib/
│   ├── main.dart           # Entry point
│   ├── app.dart            # MaterialApp root
│   ├── config/             # API URLs and env
│   ├── theme/              # PosEx branding
│   └── screens/            # UI screens
├── android/
├── ios/
└── test/
```

## Local development

```bash
cd /var/www/suzanpro/posex-app
flutter pub get
flutter run          # device or emulator
flutter test
flutter analyze
```

Build release APK locally:

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

## CI (GitHub Actions)

Workflow: `.github/workflows/posex-app.yml` (repo root)

On push/PR when `posex-app/**` changes:

1. `flutter analyze` + `flutter test`
2. `flutter build apk --release`
3. `flutter build appbundle --release`
4. Uploads APK and AAB as workflow artifacts

Manual run: **Actions → PosEx App → Run workflow**.

## Git

This app lives in the main SuzanPro monorepo under `posex-app/`.

```bash
cd /var/www/suzanpro
git add posex-app .github/workflows/posex-app.yml
git commit -m "posex-app: add Flutter mobile shell"
git push origin main
```

Optional: mirror to a dedicated repo (create `msuzan55/posex-app` on GitHub first):

```bash
/var/www/suzanpro/scripts/publish-posex-app-to-git.sh "posex-app: initial Flutter shell"
```

## Next features

- JWT login (`/api/v2/auth/login`)
- Room/SQLite offline cache + delta sync
- Camera barcode scanner
- Bluetooth thermal printer
