import 'dart:io';

import 'package:flutter/services.dart';

/// Android foreground service — previously kept a persistent "printers connected"
/// tray notification. Disabled: print server still runs while the app is open.
class PrintForegroundService {
  PrintForegroundService._();

  static const _channel = MethodChannel('lk.posex.posex_app/print_service');

  static Future<void> start({int connectedCount = 0}) async {
    // Do not show an ongoing printer-connected notification.
    await stop();
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForeground');
    } catch (_) {}
  }
}
