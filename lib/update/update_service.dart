import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'apk_installer.dart';

/// Result of an update check against the PosEx backend.
class UpdateInfo {
  UpdateInfo({
    required this.latestBuild,
    required this.versionLabel,
    required this.apkUrl,
    this.releaseNotes = '',
  });

  final int latestBuild;
  final String versionLabel;
  final String apkUrl;
  final String releaseNotes;
}

/// Checks PosEx backend for a newer APK, downloads it, then launches the
/// system installer (same signing key required for in-place update).
class UpdateService {
  UpdateService({String? apiBaseUrl})
      : apiBaseUrl = (apiBaseUrl ?? 'https://posex.lk').replaceAll(RegExp(r'/$'), '');

  final String apiBaseUrl;

  Uri get _latestUri => Uri.parse('$apiBaseUrl/api/v1/app/latest');

  /// Returns update info when backend version_code > installed buildNumber.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await http
          .get(_latestUri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latestBuild = int.tryParse('${data['version_code']}') ?? 0;
      if (latestBuild <= currentBuild) return null;

      final apkUrl = (data['apk_url'] ?? '') as String;
      if (apkUrl.isEmpty) return null;

      return UpdateInfo(
        latestBuild: latestBuild,
        versionLabel: (data['version_name'] ?? 'Update').toString(),
        apkUrl: apkUrl,
        releaseNotes: (data['release_notes'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Ensures Android can install packages, downloads APK, opens installer.
  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    if (Platform.isAndroid) {
      final allowed = await ApkInstaller.canInstallPackages();
      if (!allowed) {
        await ApkInstaller.openInstallPermissionSettings();
        throw Exception(
          'Allow PosEx to install updates in Settings, then tap Update again',
        );
      }
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/posex-update.apk');
    if (file.existsSync()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(apkUrl)));
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
          onProgress?.call(received / total);
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    if (!file.existsSync() || file.lengthSync() < 100 * 1024) {
      throw Exception('Downloaded file is invalid');
    }

    onProgress?.call(1);
    await ApkInstaller.install(file.path);
  }
}
