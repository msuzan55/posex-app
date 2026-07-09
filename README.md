# PosEx Windows App

Simple **Windows** WebView wrapper for [PosEx](https://posex.lk).

Loads `https://posex.lk/test/` in a native window (WebView2). No print server, no Android, no OTA — just the web app.

## Requirements

- Windows 10/11
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (usually preinstalled)
- Flutter stable (for local builds)
- Visual Studio with Desktop development with C++ (for local Windows builds)

## Local build

```bash
cd posex-app
flutter pub get
dart run flutter_launcher_icons
flutter run -d windows
flutter build windows --release
```

Release output: `build/windows/x64/runner/Release/`

## CI (GitHub Actions)

`.github/workflows/build-windows.yml` builds on every push to `main`:

- Analyzes & tests on Ubuntu
- Builds Windows release ZIP on `windows-latest`
- Publishes `posex-app-windows.zip` to GitHub Release `build-{run_number}`

## Publish from suzanpro → standalone GitHub repo

```bash
/var/www/suzanpro/scripts/publish-posex-app-to-git.sh "your commit message"
```

Standalone repo: https://github.com/msuzan55/posex-app

## Project layout

```
lib/main.dart          # WebView shell only
windows/               # Flutter Windows runner
.github/workflows/     # Windows CI build
assets/icon/           # App icon
```
