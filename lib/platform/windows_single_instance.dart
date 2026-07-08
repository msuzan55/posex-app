import 'dart:io';

import 'app_diagnostics.dart';

/// Ensures only one PosEx window runs on Windows (avoids WebView2 profile lock crashes).
class WindowsSingleInstance {
  WindowsSingleInstance._();

  static const _lockPort = 39217;
  static ServerSocket? _lockSocket;

  /// Returns false when another PosEx is already running (caller should exit).
  static Future<bool> acquire() async {
    if (!Platform.isWindows) return true;

    try {
      _lockSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _lockPort,
        shared: false,
      );
      await AppDiagnostics.log('INFO', 'Single-instance lock acquired');
      return true;
    } on SocketException catch (e) {
      await AppDiagnostics.log(
        'WARN',
        'PosEx already running (lock port $_lockPort): $e',
      );
      await AppDiagnostics.instance.showWindowsAlert(
        'PosEx is already open',
        'PosEx is already running on this PC. '
        'Check the taskbar or Task Manager. '
        'End any stuck posex_app.exe tasks, then open PosEx again.',
      );
      return false;
    }
  }

  static Future<void> release() async {
    await _lockSocket?.close();
    _lockSocket = null;
  }

  static Future<void> focusExistingOrExit() async {
    final ok = await acquire();
    if (!ok) {
      exit(0);
    }
  }
}
