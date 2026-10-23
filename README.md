# PosEx App (Flutter)

Native **Android** and **Windows** wrapper for [PosEx](https://posex.lk) — loads the web POS in a WebView with a built-in localhost print server on port **9753**.

## Features

| Feature | Android | Windows |
|---------|---------|---------|
| PosEx web app (`https://posex.lk/test/`) | Yes | Yes |
| Local print server (`127.0.0.1:9753`) | Yes | Yes |
| Network printers | Yes | Yes |
| USB printers | Yes | Yes (best-effort) |
| Bluetooth printers | Yes | No |
| Remote printing (WebSocket → localhost) | Yes | Yes |
| Native push (FCM) | Yes | No (use PWA push in browser) |
| In-app OTA updates (GitHub Releases) | APK | ZIP → restart |

## Local dev

```bash
cd posex-app
flutter pub get

# Android (device/emulator)
flutter run

# Windows (requires Windows + Visual Studio / WebView2)
flutter run -d windows

flutter test
flutter analyze
```

**Windows requirements:** [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (usually preinstalled on Windows 10/11).

**Opening from ZIP/RAR:** If you double-click the exe inside an archive, PosEx automatically copies itself to `%LOCALAPPDATA%\PosEx` and restarts. For first install, **PosEx-Setup.exe** is still recommended.

## CI (GitHub Actions)

`.github/workflows/build-standalone.yml` builds on every push to `main`:

- **Android:** signed release APK
- **Windows:** `posex-app-windows.zip` (portable release folder)
- **Windows installer:** `PosEx-Setup.exe`

To display a verified Windows publisher, obtain a trusted code-signing certificate
for the PosEx publisher and add GitHub Actions secrets
`POSEX_WINDOWS_PFX_BASE64` (base64 of the PFX file) and
`POSEX_WINDOWS_PFX_PASSWORD`. CI signs both `posex_app.exe` and
`PosEx-Setup.exe` when these secrets are present. Without them the build
remains unsigned and Windows can show an unknown-publisher warning. A signed
new app may still receive a SmartScreen reputation prompt initially.

On Android, the print server listens only on localhost. Settings contains an
opt-in **USB printer host auto-launch** switch for dedicated printer devices.
It is off by default so attaching USB hardware does not open the app.

Both are attached to the GitHub Release `build-{run_number}` for in-app updates.

## Publish monorepo → standalone GitHub repo

```bash
/var/www/suzanpro/scripts/publish-posex-app-to-git.sh "your commit message"
```

Standalone repo: https://github.com/msuzan55/posex-app

## Project layout

```
lib/
├── main.dart                 # WebView shell, update banner, print FAB
├── webview/                  # Android + Windows WebView bridge
├── print_server/             # HTTP server, printer manager, panel UI
├── push/                     # FCM registration (Android)
├── update/                   # GitHub OTA (APK / Windows ZIP)
└── platform/                 # Permissions & platform feature flags
```

## API

The embedded web app talks to `https://posex.lk`. The native bridge exposes `PosExNativeBridge` for auth token sync and push enable/status (Android).
