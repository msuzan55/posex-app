import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/windows_single_instance.dart';
import '../update/windows_install_paths.dart';

class PosexAppInfo {
  const PosexAppInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.installDir,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String installDir;
}

/// Windows-only shell helpers: startup, app info, wipe offline data.
class WindowsShellService {
  WindowsShellService._();

  static const _startupConfiguredKey = 'posex_startup_default_done';
  static const _startOnStartupKey = 'posex_start_on_startup';

  static bool get isSupported => Platform.isWindows;

  static Future<void> configureLaunchAtStartup() async {
    if (!isSupported) return;
    final info = await PackageInfo.fromPlatform();
    final installDir = await WindowsInstallPaths.installDir();
    launchAtStartup.setup(
      appName: info.appName,
      appPath: WindowsInstallPaths.preferredLaunchPath(installDir),
    );
  }

  /// Default: enable start-on-startup once after first install/run.
  static Future<void> ensureDefaultStartOnStartup() async {
    if (!isSupported) return;
    await configureLaunchAtStartup();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_startupConfiguredKey) == true) return;
    await setStartOnStartup(true);
    await prefs.setBool(_startupConfiguredKey, true);
  }

  static Future<bool> isStartOnStartupEnabled() async {
    if (!isSupported) return false;
    await configureLaunchAtStartup();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_startOnStartupKey)) {
      return prefs.getBool(_startOnStartupKey) ?? false;
    }
    return launchAtStartup.isEnabled();
  }

  static Future<void> setStartOnStartup(bool enabled) async {
    if (!isSupported) return;
    await configureLaunchAtStartup();
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    await prefs.setBool(_startOnStartupKey, enabled);
  }

  static Future<PosexAppInfo> getAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    final installDir = isSupported
        ? (await WindowsInstallPaths.installDir()).path
        : '';
    return PosexAppInfo(
      appName: info.appName,
      version: info.version,
      buildNumber: info.buildNumber,
      installDir: installDir,
    );
  }

  /// Wipes local prefs, WebView profile, and cached update files, then restarts.
  static Future<void> clearAllOfflineDataAndRestart() async {
    if (!isSupported) {
      throw StateError('Clear data is supported on Windows only');
    }

    final prefs = await SharedPreferences.getInstance();
    final keepStartup = prefs.getBool(_startOnStartupKey);
    final startupConfigured = prefs.getBool(_startupConfiguredKey);
    await prefs.clear();
    if (keepStartup != null) {
      await prefs.setBool(_startOnStartupKey, keepStartup);
    }
    if (startupConfigured != null) {
      await prefs.setBool(_startupConfiguredKey, startupConfigured);
    }

    final support = await getApplicationSupportDirectory();
    final webViewDir = Directory('${support.path}${Platform.pathSeparator}webview2');
    if (webViewDir.existsSync()) {
      await webViewDir.delete(recursive: true);
    }

    final temp = await getTemporaryDirectory();
    await for (final entity in temp.list()) {
      final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
      if (name.startsWith('posex-') ||
          name.startsWith('posex_') ||
          name == 'posex-update-win' ||
          name == 'posex-update-stage') {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }

    final exe = WindowsInstallPaths.preferredLaunchPath(
      Directory(File(Platform.resolvedExecutable).parent.path),
    );
    // Release the lock so the restarted instance can acquire it immediately.
    await WindowsSingleInstance.release();
    await Process.start(
      'cmd.exe',
      ['/c', exe],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    exit(0);
  }
}
