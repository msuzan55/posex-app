# PosEx Windows App

Simple **Windows** WebView wrapper for [PosEx](https://posex.lk).

Loads `https://posex.lk/test/` in a native window (WebView2).

## Download (built by GitHub Actions)

https://github.com/msuzan55/posex-app/releases/latest

1. Download **posex-app-windows.zip**
2. Unzip to a folder (e.g. `C:\PosEx\`) — do **not** run from inside the ZIP
3. Open **`Launch PosEx.cmd`**
4. If it fails to open: run **`vc_redist.x64.exe`**, install [WebView2](https://go.microsoft.com/fwlink/p/?LinkId=2124703), then retry
5. Blank/crash: delete `%APPDATA%\posex_app\webview2` and open again

## Local build (on a Windows PC)

```bash
cd posex-app
flutter pub get
dart run flutter_launcher_icons
flutter run -d windows
flutter build windows --release
```

Release output: `build/windows/x64/runner/Release/`

## Publish from suzanpro → GitHub (triggers CI build)

```bash
/var/www/suzanpro/scripts/publish-posex-app-to-git.sh "your commit message"
```

Repo: https://github.com/msuzan55/posex-app
