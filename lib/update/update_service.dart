import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

/// Checks the GitHub Releases of msuzan55/posex-app for a newer build, then
/// downloads + launches the APK installer (the OS asks the user to confirm).
class UpdateService {
  static const String _latestReleaseApi =
      'https://api.github.com/repos/msuzan55/posex-app/releases/latest';

  /// Returns update info if the latest release build number is greater than the
  /// installed one, otherwise null.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final res = await http.get(
        Uri.parse(_latestReleaseApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '') as String; // e.g. "build-42" / "v1.0.42"
      final latestBuild = _trailingInt(tag);
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

  /// Download the APK and open the installer. `onProgress` is 0..1.
  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/posex-update.apk');

    final client = http.Client();
    try {
      final resp =
          await client.send(http.Request('GET', Uri.parse(apkUrl)));
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
  }

  /// Parse the last run of digits in a tag (e.g. "v1.0.42" -> 42).
  int _trailingInt(String tag) {
    final matches = RegExp(r'\d+').allMatches(tag).toList();
    if (matches.isEmpty) return 0;
    return int.tryParse(matches.last.group(0)!) ?? 0;
  }
}
