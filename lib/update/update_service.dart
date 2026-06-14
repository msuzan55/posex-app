import 'dart:convert';
import 'dart:io';

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
    required this.apkUrl,
    this.assetId,
  });

  final int latestBuild;
  final String versionLabel;
  final String apkUrl;
  final int? assetId;
}

enum UpdateDownloadState {
  idle,
  downloading,
  ready,
  failed,
}

/// Checks GitHub Releases, auto-downloads the APK, then installs via the
/// Android package installer (same signing key required for OTA update).
class UpdateService {
  static const MethodChannel _installChannel = MethodChannel(
    'lk.posex.posex_app/apk_install',
  );

  static const String _latestReleaseApi =
      'https://api.github.com/repos/msuzan55/posex-app/releases/latest';
  static const _apkFileName = 'posex-update.apk';
  static const _prefDownloadedBuild = 'posex_downloaded_build';

  UpdateDownloadState state = UpdateDownloadState.idle;
  double downloadProgress = 0;
  String? lastError;

  /// Returns update info if the latest release build number is greater than the
  /// installed one, otherwise null.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'PosEx-Android-Updater',
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
      String? apkUrl;
      int? assetId;
      for (final a in assets.cast<Map<String, dynamic>>()) {
        final name = (a['name'] ?? '') as String;
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          assetId = int.tryParse('${a['id']}');
          break;
        }
      }
      if (apkUrl == null) {
        lastError = 'No APK found in latest GitHub release';
        return null;
      }

      return UpdateInfo(
        latestBuild: latestBuild,
        versionLabel: (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : tag,
        apkUrl: apkUrl,
        assetId: assetId,
      );
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// Cache dir is exposed via FileProvider `cache-path` (required for install).
  Future<File> apkFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_apkFileName');
  }

  Future<bool> isDownloadReady(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBuild = prefs.getInt(_prefDownloadedBuild) ?? 0;
    if (savedBuild != info.latestBuild) return false;
    final file = await apkFile();
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

  /// Download APK to app cache. Safe to call multiple times.
  Future<void> downloadUpdate(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (state == UpdateDownloadState.downloading) return;

    state = UpdateDownloadState.downloading;
    downloadProgress = 0;
    lastError = null;

    final file = await apkFile();
    final partial = File('${file.path}.part');
    if (file.existsSync()) await file.delete();
    if (partial.existsSync()) await partial.delete();

    final client = http.Client();
    try {
      final uri = info.assetId != null
          ? Uri.parse(
              'https://api.github.com/repos/msuzan55/posex-app/releases/assets/${info.assetId}',
            )
          : Uri.parse(info.apkUrl);

      final request = http.Request('GET', uri);
      request.headers.addAll(const {
        'Accept': 'application/octet-stream',
        'User-Agent': 'PosEx-Android-Updater',
      });

      final resp = await client.send(request).timeout(const Duration(minutes: 10));
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
      if (!_isValidApk(file)) {
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

  /// Launch Android package installer for the downloaded APK.
  Future<void> installDownloadedApk() async {
    if (!Platform.isAndroid) {
      throw Exception('Updates are supported on Android only');
    }

    final file = await apkFile();
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
