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
      if (dir.existsSync()) return dir;
    }

    final exe = File(Platform.resolvedExecutable);
    final dir = exe.parent;
    await prefs.setString(_installDirKey, dir.path);
    return dir;
  }

  /// Call once at startup so the install path is pinned before any OTA runs from temp.
  static Future<void> rememberCurrentInstallDir() async {
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
ping 127.0.0.1 -n 3 >nul
robocopy "$source" "$target" /E /IS /IT /R:5 /W:2 /NFL /NDL /NJH /NJS /NC /NS /NP
if %ERRORLEVEL% GEQ 8 exit /b %ERRORLEVEL%
start "" "$exe"
del "%~f0"
''');
    return script;
  }
}
