import 'dart:io';

import 'package:flutter/services.dart';

/// Native Android APK install via FileProvider (reliable vs open_filex).
class ApkInstaller {
  ApkInstaller._();

  static const _channel = MethodChannel('lk.posex.posex_app/install');

  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return true;
    final ok = await _channel.invokeMethod<bool>('canInstallPackages');
    return ok ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<void> install(String apkPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK install is Android only');
    }
    await _channel.invokeMethod<void>('installApk', {'path': apkPath});
  }
}
