import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Android-only runtime permissions (camera, storage, Bluetooth, notifications).
Future<void> requestAppPermissions() async {
  if (!Platform.isAndroid) return;

  await [
    Permission.camera,
    Permission.photos,
    Permission.storage,
    Permission.notification,
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ].request();
}
