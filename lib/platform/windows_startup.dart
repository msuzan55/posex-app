import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Extra Windows-only startup checks after the install folder is resolved.
class WindowsStartup {
  WindowsStartup._();

  static Future<String?> checkRuntimeRequirements() async {
    if (!Platform.isWindows) return null;

    final webViewVersion = await WebViewEnvironment.getAvailableVersion();
    if (webViewVersion == null) {
      return 'Microsoft Edge WebView2 Runtime is not installed.\n\n'
          'Download and install it from:\n'
          'https://go.microsoft.com/fwlink/p/?LinkId=2124703\n\n'
          'Then restart PosEx.';
    }

    return null;
  }
}
