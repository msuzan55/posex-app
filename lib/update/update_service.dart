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
  });

  final int latestBuild;
  final String versionLabel;
  final String apkUrl;
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
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '') as String;
      final latestBuild = _parseBuildNumber(tag);
      if (latestBuild <= currentBuild) return null;

      final assets = (data['assets'] as List?) ?? const [];
      String? apkUrl;
      for (final a in assets.cast<Map<String, dynamic>>()) {
        final name = (a['name'] ?? '') as String;
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      return UpdateInfo(
        latestBuild: latestBuild,
        versionLabel: (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : tag,
        apkUrl: apkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> apkFile() async {
    final dir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return File('${updatesDir.path}/$_apkFileName');
  }

  Future<bool> isDownloadReady(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBuild = prefs.getInt(_prefDownloadedBuild) ?? 0;
    if (savedBuild != info.latestBuild) return false;
    final file = await apkFile();
    return file.existsSync() && file.lengthSync() > 4096;
  }

  /// Download APK to app storage. Safe to call multiple times.
  Future<void> downloadUpdate(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (state == UpdateDownloadState.downloading) return;

    state = UpdateDownloadState.downloading;
    downloadProgress = 0;
    lastError = null;

    final file = await apkFile();
    if (file.existsSync()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(info.apkUrl)));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (${resp.statusCode})');
      }

      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
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

      if (!file.existsSync() || file.lengthSync() < 4096) {
        throw Exception('Downloaded file is incomplete');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefDownloadedBuild, info.latestBuild);
      state = UpdateDownloadState.ready;
      downloadProgress = 1;
    } catch (e) {
      state = UpdateDownloadState.failed;
      lastError = e.toString();
      if (file.existsSync()) {
        await file.delete();
      }
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
    if (!file.existsSync()) {
      throw Exception('Update file missing — download again');
    }

    final canInstall =
        await _installChannel.invokeMethod<bool>('canRequestPackageInstalls') ??
            false;
    if (!canInstall) {
      await _installChannel.invokeMethod<void>('openInstallPermissionSettings');
      throw Exception(
        'Allow PosEx to install updates (Unknown apps), then tap Update again.',
      );
    }

    await _installChannel.invokeMethod<void>('installApk', {
      'path': file.path,
    });
  }

  int _parseBuildNumber(String tag) {
    // Prefer explicit build-123 tags from CI.
    final buildMatch = RegExp(r'build-(\d+)', caseSensitive: false).firstMatch(tag);
    if (buildMatch != null) {
      return int.tryParse(buildMatch.group(1)!) ?? 0;
    }
    final matches = RegExp(r'\d+').allMatches(tag).toList();
    if (matches.isEmpty) return 0;
    return int.tryParse(matches.last.group(0)!) ?? 0;
  }
}
