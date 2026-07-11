import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/app_diagnostics.dart';
import '../platform/windows_single_instance.dart';

const _installDirKey = 'posex_windows_install_dir';

/// Result of pre-launch checks on Windows.
class WindowsLaunchCheck {
  const WindowsLaunchCheck._({
    this.blockMessage,
    this.relaunching = false,
  });

  final String? blockMessage;
  final bool relaunching;

  bool get canContinue => blockMessage == null && !relaunching;

  static const ready = WindowsLaunchCheck._();

  static WindowsLaunchCheck blocked(String message) =>
      WindowsLaunchCheck._(blockMessage: message);

  static const relaunchPending = WindowsLaunchCheck._(relaunching: true);
}

/// Resolves and remembers the folder where PosEx is installed/run from.
class WindowsInstallPaths {
  WindowsInstallPaths._();

  static Directory get currentExeDir => File(Platform.resolvedExecutable).parent;

  /// Prefer launch_posex.cmd so working directory is always the install folder.
  static String preferredLaunchPath([Directory? dir]) {
    final root = dir ?? currentExeDir;
    final launcher =
        File('${root.path}${Platform.pathSeparator}launch_posex.cmd');
    if (launcher.existsSync()) return launcher.path;
    return File('${root.path}${Platform.pathSeparator}posex_app.exe').path;
  }

  static Directory permanentInstallDir() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    if (localAppData.isNotEmpty) {
      return Directory('$localAppData${Platform.pathSeparator}PosEx');
    }
    return Directory(_defaultInstallPath());
  }

  /// True when PosEx is running from WinRAR/7-Zip temp or another unstable folder.
  static bool isUnsafeRunLocation([Directory? dir]) {
    final rootDir = dir ?? currentExeDir;
    final path = _normalizedPath(rootDir.path);

    // If it's already in the permanent install directory, it's safe.
    final permanentPath = _normalizedPath(permanentInstallDir().path);
    if (path == permanentPath || path.startsWith('$permanentPath\\')) {
      return false;
    }

    // Check if it's running from the system temp directory.
    final tempPath = _normalizedPath(Directory.systemTemp.path);
    if (path.startsWith(tempPath) || path.contains('$tempPath\\')) {
      return true;
    }

    // Standard temp/tmp pattern checks, but avoid matching AppData unless it is under Temp.
    if (path.contains(r'\temp\') || path.contains(r'\tmp\')) {
      final localAppData = _normalizedPath(Platform.environment['LOCALAPPDATA'] ?? '');
      if (localAppData.isNotEmpty && path.startsWith(localAppData)) {
        final appDataTemp = '$localAppData\\temp';
        if (path.startsWith(appDataTemp)) {
          return true;
        }
        return false;
      }
      return true;
    }

    if (path.contains(r'rar$')) return true;
    if (path.contains(r'\7z') && path.contains(r'\temp')) return true;
    return false;
  }

  /// Returns null when the release folder next to [dir] looks complete.
  static String? validateInstallBundle([Directory? dir]) {
    final root = dir ?? currentExeDir;
    final exe = File('${root.path}${Platform.pathSeparator}posex_app.exe');
    if (!exe.existsSync()) {
      return 'posex_app.exe is missing from the app folder.';
    }

    final flutterDll =
        File('${root.path}${Platform.pathSeparator}flutter_windows.dll');
    if (!flutterDll.existsSync()) {
      return 'flutter_windows.dll is missing. Extract the full ZIP or run PosEx-Setup.exe.';
    }

    final dataDir = Directory('${root.path}${Platform.pathSeparator}data');
    if (!dataDir.existsSync()) {
      return 'The data folder is missing. Extract the full ZIP or run PosEx-Setup.exe.';
    }

    final assets =
        Directory('${root.path}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets');
    if (!assets.existsSync()) {
      return 'App files are incomplete. Extract the full ZIP or run PosEx-Setup.exe.';
    }

    final icu = File('${root.path}${Platform.pathSeparator}data${Platform.pathSeparator}icudtl.dat');
    if (!icu.existsSync()) {
      return 'App data (icudtl.dat) is missing. Extract the full ZIP or run PosEx-Setup.exe.';
    }

    return null;
  }

  static String unsafeLocationUserMessage(String? bundleError) {
    if (bundleError != null) {
      return 'PosEx was opened from a ZIP/RAR archive without extracting it fully.\n\n'
          '$bundleError\n\n'
          'Fix:\n'
          '1. Right-click the ZIP → Extract All… to a folder such as C:\\PosEx\n'
          '2. Run posex_app.exe from that folder\n\n'
          'Or install with PosEx-Setup.exe (recommended).';
    }
    return 'PosEx cannot run from a temporary archive folder. '
        'Install with PosEx-Setup.exe or extract the full ZIP first.';
  }

  /// Validates the bundle and, when needed, copies PosEx to a permanent folder
  /// then relaunches from there.
  static Future<WindowsLaunchCheck> prepareLaunch() async {
    if (!Platform.isWindows) return WindowsLaunchCheck.ready;

    final current = currentExeDir;
    final bundleError = validateInstallBundle(current);
    if (bundleError != null) {
      if (isUnsafeRunLocation(current)) {
        return WindowsLaunchCheck.blocked(
          unsafeLocationUserMessage(bundleError),
        );
      }
      return WindowsLaunchCheck.blocked(bundleError);
    }

    if (!isUnsafeRunLocation(current)) {
      await rememberCurrentInstallDir();
      return WindowsLaunchCheck.ready;
    }

    final target = permanentInstallDir();
    try {
      if (!isUnsafeRunLocation(target) && validateInstallBundle(target) == null) {
        await _rememberInstallDir(target);
        await AppDiagnostics.instance.markCleanExit();
        await _relaunchFrom(target);
        return WindowsLaunchCheck.relaunchPending;
      }

      await AppDiagnostics.log(
        'INFO',
        'Copying PosEx from unstable folder ${current.path} to ${target.path}',
      );
      await _copyInstallFolder(from: current, to: target);
      final copiedOk = validateInstallBundle(target);
      if (copiedOk != null) {
        throw StateError('Copied install is incomplete: $copiedOk');
      }
      await _rememberInstallDir(target);
      await AppDiagnostics.instance.markCleanExit();
      await _relaunchFrom(target);
      return WindowsLaunchCheck.relaunchPending;
    } catch (e, st) {
      await AppDiagnostics.logError('Permanent install failed', e, st);
      return WindowsLaunchCheck.blocked(
        '${unsafeLocationUserMessage(null)}\n\nAutomatic install failed: $e',
      );
    }
  }

  static Future<Directory> installDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_installDirKey);
    if (saved != null && saved.isNotEmpty) {
      final dir = Directory(saved);
      if (_looksLikePosexInstall(dir)) return dir;
    }

    final currentDir = currentExeDir;
    if (_looksLikePosexInstall(currentDir)) {
      await _rememberInstallDir(currentDir);
      return currentDir;
    }

    final defaultDir = Directory(_defaultInstallPath());
    if (_looksLikePosexInstall(defaultDir)) {
      await _rememberInstallDir(defaultDir);
      return defaultDir;
    }

    final permanent = permanentInstallDir();
    if (_looksLikePosexInstall(permanent)) {
      await _rememberInstallDir(permanent);
      return permanent;
    }

    await _rememberInstallDir(currentDir);
    return currentDir;
  }

  /// Call once at startup so the install path is pinned before any OTA runs from temp.
  static Future<void> rememberCurrentInstallDir() async {
    final currentDir = currentExeDir;
    if (_looksLikePosexInstall(currentDir)) {
      await _rememberInstallDir(currentDir);
      return;
    }
    await installDir();
  }

  static Future<void> _rememberInstallDir(Directory dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_installDirKey, dir.path);
  }

  static Future<void> _relaunchFrom(Directory dir) async {
    final exe = File('${dir.path}${Platform.pathSeparator}posex_app.exe');
    if (!exe.existsSync()) {
      throw StateError('posex_app.exe not found in ${dir.path}');
    }

    // Release the single-instance lock before starting the new process so the
    // new instance can acquire it without hitting the "already running" check.
    await WindowsSingleInstance.release();

    final launcher = File('${dir.path}${Platform.pathSeparator}launch_posex.cmd');
    if (launcher.existsSync()) {
      await Process.start(
        'cmd.exe',
        ['/c', launcher.path],
        mode: ProcessStartMode.detached,
        workingDirectory: dir.path,
      );
    } else {
      await Process.start(
        exe.path,
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: dir.path,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  static Future<void> _copyInstallFolder({
    required Directory from,
    required Directory to,
  }) async {
    if (to.existsSync()) {
      await to.delete(recursive: true);
    }
    await to.create(recursive: true);

    if (Platform.isWindows) {
      final result = await Process.run('robocopy', [
        from.path,
        to.path,
        '/E',
        '/IS',
        '/IT',
        '/R:5',
        '/W:1',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NC',
        '/NS',
        '/NP',
      ]);
      final code = result.exitCode;
      if (code >= 8) {
        throw StateError(
          'Copy failed (robocopy exit $code): ${result.stderr}',
        );
      }
    } else {
      await _copyInstallFolderDart(from: from, to: to);
    }

    final launcher = File(
      '${from.path}${Platform.pathSeparator}launch_posex.cmd',
    );
    if (launcher.existsSync()) {
      await launcher.copy(
        '${to.path}${Platform.pathSeparator}launch_posex.cmd',
      );
    }
  }

  static Future<void> _copyInstallFolderDart({
    required Directory from,
    required Directory to,
  }) async {
    await for (final entity in from.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final destPath = '${to.path}${Platform.pathSeparator}$name';
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    if (!to.existsSync()) {
      await to.create(recursive: true);
    }
    await for (final entity in from.list(recursive: false, followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final destPath = '${to.path}${Platform.pathSeparator}$name';
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }

  /// Hidden helper: wait for PosEx-Setup.exe, then relaunch PosEx (no cmd window).
  static Future<File> writeSilentSetupLauncher({
    required File setupExe,
    required File targetExe,
  }) async {
    final temp = await getTemporaryDirectory();
    final script = File('${temp.path}/posex_setup_restart.vbs');
    final setup = setupExe.path.replaceAll('/', r'\');
    final exe = targetExe.path.replaceAll('/', r'\');

    await script.writeAsString('''
Set sh = CreateObject("WScript.Shell")
rc = sh.Run("""$setup"" /SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS", 0, True)
If rc = 0 Or rc = 3010 Or rc = 1641 Then
  sh.Run """$exe""", 1, False
End If
Set fso = CreateObject("Scripting.FileSystemObject")
On Error Resume Next
fso.DeleteFile WScript.ScriptFullName
''');
    return script;
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
    if (validateInstallBundle(dir) != null) return false;
    return !isUnsafeRunLocation(dir);
  }

  static String _defaultInstallPath() {
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    return '$pf\\PosEx';
  }

  static String _normalizedPath(String path) {
    return path.replaceAll('/', r'\').toLowerCase();
  }
}
