# AGENTS.md

## Cursor Cloud specific instructions

PosEx App is a single Flutter app (Android + Windows) that wraps the hosted web POS at
`https://posex.lk` in a WebView and runs an embedded localhost print server on port `9753`.
There is no backend or database in this repo. Standard build/run/test commands live in
`README.md` and `pubspec.yaml`; this section only records the non-obvious, durable caveats for
running it inside a Cursor Cloud VM.

### Toolchain locations (already installed in the VM image)
- Flutter SDK `3.44.8` (stable, Dart `3.12.2`) is at `~/flutter`, symlinked into `/usr/local/bin`
  (`flutter`, `dart`), so it is on `PATH` for all shells including the update script.
- Android SDK is at `~/Android/sdk` (`ANDROID_HOME`/`ANDROID_SDK_ROOT`, also exported in `~/.bashrc`):
  platform-tools, `platforms;android-36`, `build-tools;36.0.0`, `emulator`, and a
  `system-images;android-36;google_apis;x86_64` AVD named `posex_test`. Android SDK licenses are
  already accepted. The first `flutter run`/APK build auto-installs the matching NDK + CMake.
- System JDK is 21. Gradle `9.1.0` + AGP `9.0.1` build fine on JDK 21 (CI uses JDK 17, but 21 works).
- `android/app/google-services.json` and `lib/firebase_options.dart` are committed, so Android
  builds succeed without extra Firebase setup.

### Build / lint / test (verified working, no device needed)
- `flutter pub get`, `flutter analyze --fatal-infos` (lint), `flutter test` all pass on Linux with
  no emulator. `flutter build apk --debug` also succeeds.

### Running the app end-to-end (Android emulator) — important gotchas
This app has no web or Linux-desktop target (its plugins are Android/Windows only), so the only way
to run it on this Linux VM is the Android emulator. The emulator works but is degraded here:

- Nested KVM is BROKEN in this VM: creating a KVM vCPU triggers a host
  `kernel BUG at arch/x86/kvm/x86.c:702 (kvm_spurious_fault)`, so a KVM-accelerated guest hangs
  before the kernel boots. `emulator -accel-check` reports KVM "usable" but it still crashes — do
  not trust it. Launch the emulator with software CPU: `-no-accel`. (If you still want KVM perms for
  other tooling, `/dev/kvm` is `root:103` each boot; `sudo chmod 666 /dev/kvm` grants access, but it
  will not fix the nested-KVM crash.)
- Boot is SLOW under software emulation: expect ~8-15 min to reach `sys.boot_completed=1`.
  Launch example (run in a tmux session, on `DISPLAY=:1` which is the VNC desktop):
  `emulator -avd posex_test -no-accel -gpu swiftshader_indirect -no-snapshot -no-boot-anim`
- Emulator networking often comes up with NO IP (WiFi image; `wlan0` shows `NO-CARRIER`, `eth0`
  DOWN). Kick it after boot with:
  `adb root; adb shell 'ip link set eth0 up'; adb shell 'svc wifi disable; sleep 2; svc wifi enable'`
  then `adb shell 'ip route add default via 10.0.2.2 dev wlan0; setprop net.dns1 10.0.2.3'`.
  After this, `ping posex.lk` / `8.8.8.8` from inside the guest works.
- No hardware GPU: the emulator uses SwiftShader (software GL). Flutter's own UI renders, but the
  Chromium **WebView** GPU process crashes on SwiftShader (`crashpad` -> `SIGTRAP`), and the heavy
  `posex.lk` SPA also ANRs under the slow software CPU. Net effect: build/install/launch and the
  app's native Flutter shell all work (you will see the loading spinner + orange print/settings FAB),
  but fully rendering the remote POS page inside the WebView is not reliable on this emulator. This
  is an infra limitation of the nested VM (no GPU, no nested KVM), not a code problem. On real
  hardware / a GPU-enabled emulator the WebView loads normally.
- The embedded print server (`GET /status`, `POST /print` on `127.0.0.1:9753`) only binds after the
  WebView host mounts, which coincides with the WebView instability above, so it is hard to exercise
  on this emulator. Reach it from the host via `adb forward tcp:9753 tcp:9753`.

### Notes
- Do not `pkill -f` the emulator; kill the specific `qemu-system-x86_64 -avd posex_test` PID.
- `flutter run` uses Impeller (OpenGLES) by default; you can pass `--no-enable-impeller` (Skia), but
  neither backend avoids the Chromium-WebView-on-SwiftShader crash described above.
