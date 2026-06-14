import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installDirKey = 'posex_windows_install_dir';

/// Resolves and remembers the folder where PosEx is installed/run from.
class WindowsInstallPaths {
  WindowsInstallPaths._();

  static Future<Directory> installDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_installDirKey);
    if (saved != null && saved.isNotEmpty) {
      final dir = Directory(saved);
      if (_looksLikePosexInstall(dir)) return dir;
    }

    // Prefer current executable location only if it already looks like PosEx.
    // This avoids pinning temp extraction paths after an update.
    final currentDir = File(Platform.resolvedExecutable).parent;
    if (_looksLikePosexInstall(currentDir)) {
      await prefs.setString(_installDirKey, currentDir.path);
      return currentDir;
    }

    // Fallback to default installer path.
    final defaultDir = Directory(_defaultInstallPath());
    if (_looksLikePosexInstall(defaultDir)) {
      await prefs.setString(_installDirKey, defaultDir.path);
      return defaultDir;
    }

    // Last resort: keep current executable directory.
    await prefs.setString(_installDirKey, currentDir.path);
    return currentDir;
  }

  /// Call once at startup so the install path is pinned before any OTA runs from temp.
  static Future<void> rememberCurrentInstallDir() async {
    final currentDir = File(Platform.resolvedExecutable).parent;
    if (_looksLikePosexInstall(currentDir)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_installDirKey, currentDir.path);
      return;
    }
    await installDir();
  }

  static Future<File> writeInPlaceUpdater({
    required Directory sourceDir,
    required Directory targetDir,
    required String exeName,
  }) async {
    final temp = await getTemporaryDirectory();
    final script = File('${temp.path}/posex_apply_update.bat');
    final source = sourceDir.path.replaceAll('/', '\\');
    final target = targetDir.path.replaceAll('/', '\\');
    final exe = '$target\\$exeName';

    // Wait for this app to exit, overwrite binaries in the install folder, restart.
    // User data (login, IndexedDB) lives in AppData — not touched by this copy.
    await script.writeAsString('''
@echo off
setlocal enableextensions
ping 127.0.0.1 -n 3 >nul
if not exist "$target\\$exeName" (
  echo Target executable missing in "$target"
  exit /b 3
)
robocopy "$source" "$target" /E /IS /IT /R:5 /W:2 /NFL /NDL /NJH /NJS /NC /NS /NP
if %ERRORLEVEL% GEQ 8 exit /b %ERRORLEVEL%
start "" "$exe"
del "%~f0"
''');
    return script;
  }

  static bool _looksLikePosexInstall(Directory dir) {
    if (!dir.existsSync()) return false;
    final exe = File('${dir.path}${Platform.pathSeparator}posex_app.exe');
    if (!exe.existsSync()) return false;
    final lower = dir.path.toLowerCase();
    if (lower.contains('${Platform.pathSeparator}temp') ||
        lower.contains('${Platform.pathSeparator}tmp')) {
      return false;
    }
    return true;
  }

  static String _defaultInstallPath() {
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    return '$pf\\PosEx';
  }
}
