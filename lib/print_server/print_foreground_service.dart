import 'dart:io';

import 'package:flutter/services.dart';

/// Android foreground service — keeps the app process alive for remote printing.
class PrintForegroundService {
  PrintForegroundService._();

  static const _channel = MethodChannel('lk.posex.posex_app/print_service');

  static Future<void> start({int connectedCount = 0}) async {
    if (!Platform.isAndroid) return;
    if (connectedCount <= 0) return;
    try {
      await _channel.invokeMethod<void>('startForeground', {
        'connectedCount': connectedCount,
      });
    } catch (_) {
      // Non-fatal — print server still runs while app is foregrounded.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForeground');
    } catch (_) {}
  }
}
