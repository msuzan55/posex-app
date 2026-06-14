import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of an update check.
class UpdateInfo {
  UpdateInfo({
    required this.latestBuild,
    required this.versionLabel,
    required this.downloadUrl,
    this.assetId,
    required this.isWindowsZip,
  });

  final int latestBuild;
  final String versionLabel;
  final String downloadUrl;
  final int? assetId;
  final bool isWindowsZip;
}

enum UpdateDownloadState {
  idle,
  downloading,
  ready,
  failed,
}

/// Checks GitHub Releases, auto-downloads the update asset, then installs via
/// the Android package installer or launches the Windows build from cache.
class UpdateService {
  static const MethodChannel _installChannel = MethodChannel(
    'lk.posex.posex_app/apk_install',
  );

  static const String _latestReleaseApi =
      'https://api.github.com/repos/msuzan55/posex-app/releases/latest';
  static const _apkFileName = 'posex-update.apk';
  static const _windowsZipFileName = 'posex-update-windows.zip';
  static const _windowsExtractDirName = 'posex-update-win';
  static const _prefDownloadedBuild = 'posex_downloaded_build';

  UpdateDownloadState state = UpdateDownloadState.idle;
  double downloadProgress = 0;
  String? lastError;

  bool get _isWindows => Platform.isWindows;

  String get _userAgent =>
      _isWindows ? 'PosEx-Windows-Updater' : 'PosEx-Android-Updater';

  /// Returns update info if the latest release build number is greater than the
  /// installed one, otherwise null.
  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid && !Platform.isWindows) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        lastError = 'Update check failed (${res.statusCode})';
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '') as String;
      final latestBuild = _parseBuildNumber(tag);
      if (latestBuild <= currentBuild) return null;

      final assets = (data['assets'] as List?) ?? const [];
      String? downloadUrl;
      int? assetId;
      var isWindowsZip = false;

      for (final a in assets.cast<Map<String, dynamic>>()) {
        final name = (a['name'] ?? '') as String;
        final lower = name.toLowerCase();
        if (_isWindows) {
          if (lower.endsWith('.zip')) {
            downloadUrl = a['browser_download_url'] as String?;
            assetId = int.tryParse('${a['id']}');
            isWindowsZip = true;
            break;
          }
        } else if (lower.endsWith('.apk')) {
          downloadUrl = a['browser_download_url'] as String?;
          assetId = int.tryParse('${a['id']}');
          break;
        }
      }

      if (downloadUrl == null) {
        lastError = _isWindows
            ? 'No Windows ZIP found in latest GitHub release'
            : 'No APK found in latest GitHub release';
        return null;
      }

      return UpdateInfo(
        latestBuild: latestBuild,
        versionLabel: (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : tag,
        downloadUrl: downloadUrl,
        assetId: assetId,
        isWindowsZip: isWindowsZip,
      );
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<File> _updateFile(UpdateInfo info) async {
    final dir = await getTemporaryDirectory();
    final name = info.isWindowsZip ? _windowsZipFileName : _apkFileName;
    return File('${dir.path}/$name');
  }

  Future<bool> isDownloadReady(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBuild = prefs.getInt(_prefDownloadedBuild) ?? 0;
    if (savedBuild != info.latestBuild) return false;
    final file = await _updateFile(info);
    if (info.isWindowsZip) {
      return _isValidZip(file) && await _windowsExeFromDownload() != null;
    }
    return _isValidApk(file);
  }

  bool _isValidApk(File file) {
    if (!file.existsSync()) return false;
    if (file.lengthSync() < 4096) return false;
    try {
      final raf = file.openSync(mode: FileMode.read);
      final header = raf.readSync(4);
      raf.closeSync();
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4b &&
          header[2] == 0x03 &&
          header[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  bool _isValidZip(File file) => _isValidApk(file);

  /// Download update to app cache. Safe to call multiple times.
  Future<void> downloadUpdate(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (state == UpdateDownloadState.downloading) return;

    state = UpdateDownloadState.downloading;
    downloadProgress = 0;
    lastError = null;

    final file = await _updateFile(info);
    final partial = File('${file.path}.part');
    if (file.existsSync()) await file.delete();
    if (partial.existsSync()) await partial.delete();

    final client = http.Client();
    try {
      final uri = info.assetId != null
          ? Uri.parse(
              'https://api.github.com/repos/msuzan55/posex-app/releases/assets/${info.assetId}',
            )
          : Uri.parse(info.downloadUrl);

      final request = http.Request('GET', uri);
      request.headers.addAll({
        'Accept': 'application/octet-stream',
        'User-Agent': _userAgent,
      });

      final resp =
          await client.send(request).timeout(const Duration(minutes: 10));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (${resp.statusCode})');
      }

      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = partial.openWrite();
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          downloadProgress = received / total;
          onProgress?.call(downloadProgress);
        }
      }
      await sink.flush();
      await sink.close();

      if (!partial.existsSync() || partial.lengthSync() < 4096) {
        throw Exception('Downloaded file is incomplete');
      }

      await partial.rename(file.path);

      if (info.isWindowsZip) {
        if (!_isValidZip(file)) {
          await file.delete();
          throw Exception('Downloaded file is not a valid ZIP');
        }
        await _extractWindowsZip(file);
        if (await _windowsExeFromDownload() == null) {
          await file.delete();
          throw Exception('Windows update ZIP does not contain posex_app.exe');
        }
      } else if (!_isValidApk(file)) {
        await file.delete();
        throw Exception('Downloaded file is not a valid APK');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefDownloadedBuild, info.latestBuild);
      state = UpdateDownloadState.ready;
      downloadProgress = 1;
    } catch (e) {
      state = UpdateDownloadState.failed;
      lastError = e.toString().replaceFirst('Exception: ', '');
      if (partial.existsSync()) await partial.delete();
      if (file.existsSync()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Install the downloaded update for the current platform.
  Future<void> installDownloadedUpdate() async {
    if (Platform.isAndroid) {
      await installDownloadedApk();
      return;
    }
    if (Platform.isWindows) {
      await installDownloadedWindowsBuild();
      return;
    }
    throw Exception('Updates are supported on Android and Windows only');
  }

  /// Launch Android package installer for the downloaded APK.
  Future<void> installDownloadedApk() async {
    if (!Platform.isAndroid) {
      throw Exception('APK install is supported on Android only');
    }

    final file = await _updateFile(
      UpdateInfo(
        latestBuild: 0,
        versionLabel: '',
        downloadUrl: '',
        isWindowsZip: false,
      ),
    );
    if (!_isValidApk(file)) {
      throw Exception('Update file missing or corrupt — download again');
    }

    final canInstall =
        await _installChannel.invokeMethod<bool>('canRequestPackageInstalls') ??
            false;
    if (!canInstall) {
      await _installChannel.invokeMethod<void>('openInstallPermissionSettings');
      throw Exception(
        'Allow PosEx to install updates, then tap the banner again.',
      );
    }

    final result = await _installChannel.invokeMethod<bool>('installApk', {
      'path': file.path,
    });
    if (result != true) {
      throw Exception('Could not open the Android installer');
    }
  }

  Future<Directory> _windowsExtractDir() async {
    final dir = await getTemporaryDirectory();
    return Directory('${dir.path}/$_windowsExtractDirName');
  }

  Future<File?> _windowsExeFromDownload() async {
    final extractDir = await _windowsExtractDir();
    if (!extractDir.existsSync()) return null;

    final direct = File('${extractDir.path}/posex_app.exe');
    if (direct.existsSync()) return direct;

    await for (final entity in extractDir.list(recursive: true)) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('posex_app.exe')) {
        return entity;
      }
    }
    return null;
  }

  Future<void> _extractWindowsZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final extractDir = await _windowsExtractDir();
    if (extractDir.existsSync()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    for (final file in archive) {
      if (!file.isFile) continue;
      final out = File('${extractDir.path}/${file.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>);
    }
  }

  /// Launch the downloaded Windows build and exit this process.
  Future<void> installDownloadedWindowsBuild() async {
    if (!Platform.isWindows) {
      throw Exception('Windows updates are supported on Windows only');
    }

    final zipFile = await _updateFile(
      UpdateInfo(
        latestBuild: 0,
        versionLabel: '',
        downloadUrl: '',
        isWindowsZip: true,
      ),
    );
    if (!_isValidZip(zipFile)) {
      throw Exception('Update file missing or corrupt — download again');
    }

    if (await _windowsExeFromDownload() == null) {
      await _extractWindowsZip(zipFile);
    }

    final exe = await _windowsExeFromDownload();
    if (exe == null) {
      throw Exception('Could not find posex_app.exe in the update package');
    }

    await Process.start(
      exe.path,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  int _parseBuildNumber(String tag) {
    final buildMatch =
        RegExp(r'build-(\d+)', caseSensitive: false).firstMatch(tag);
    if (buildMatch != null) {
      return int.tryParse(buildMatch.group(1)!) ?? 0;
    }
    final matches = RegExp(r'\d+').allMatches(tag).toList();
    if (matches.isEmpty) return 0;
    return int.tryParse(matches.last.group(0)!) ?? 0;
  }
}
