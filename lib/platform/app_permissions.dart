import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Notifications only at startup. Camera / photos / Bluetooth dialogs used to
/// stack on launch and made the POS look frozen (Chrome never does this).
Future<void> requestAppPermissions() async {
  if (!Platform.isAndroid) return;
  await Permission.notification.request();
}

/// Camera + gallery when the WebView actually asks (product photos, uploads).
Future<void> requestMediaPermissions() async {
  if (!Platform.isAndroid) return;
  await [
    Permission.camera,
    Permission.photos,
    Permission.storage,
  ].request();
}

/// Bluetooth when the cashier opens printer settings, not at app start.
Future<void> requestPrintPermissions() async {
  if (!Platform.isAndroid) return;
  await [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ].request();
}
