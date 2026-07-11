import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_diagnostics.dart';

/// Windows-only startup: WebView2, window shell, and shared WebView environment.
class WindowsStartup {
  WindowsStartup._();

  static WebViewEnvironment? sharedWebViewEnvironment;

  static const _vcRedistUrl =
      'https://aka.ms/vs/17/release/vc_redist.x64.exe';

  static Future<String?> checkRuntimeRequirements() async {
    if (!Platform.isWindows) return null;

    final vcError = _checkVcRedist();
    if (vcError != null) return vcError;

    final webViewVersion = await WebViewEnvironment.getAvailableVersion();
    if (webViewVersion == null) {
      return 'Microsoft Edge WebView2 Runtime is not installed.\n\n'
          'Download and install it from:\n'
          'https://go.microsoft.com/fwlink/p/?LinkId=2124703\n\n'
          'Then restart PosEx.';
    }

    await AppDiagnostics.log('INFO', 'WebView2 runtime version: $webViewVersion');
    return null;
  }

  static String? _checkVcRedist() {
    final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final sys32 = '$sysRoot${Platform.pathSeparator}System32';
    const required = [
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'msvcp140.dll',
    ];

    final missing = <String>[];
    for (final dll in required) {
      if (!File('$sys32${Platform.pathSeparator}$dll').existsSync()) {
        missing.add(dll);
      }
    }
    if (missing.isEmpty) return null;

    final installDir = File(Platform.resolvedExecutable).parent;
    final bundledRedist = File(
      '${installDir.path}${Platform.pathSeparator}vc_redist.x64.exe',
    );
    final bundledHint = bundledRedist.existsSync()
        ? '\n\nRun this file as Administrator:\n${bundledRedist.path}'
        : '';

    return 'Microsoft Visual C++ Runtime is missing (${missing.join(', ')}).\n\n'
        'PosEx needs the Visual C++ 2015–2022 Redistributable (x64).\n\n'
        'Fix:\n'
        '1. Install PosEx using PosEx-Setup.exe (recommended)\n'
        '2. Or download and run:\n'
        '   $_vcRedistUrl'
        '$bundledHint\n\n'
        'Then restart PosEx.';
  }

  static Future<void> setupWindow() async {
    if (!Platform.isWindows) return;

    await windowManager.ensureInitialized();

    // Normal title bar is more stable on some Windows PCs than hidden + custom bar.
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(1024, 640),
      center: true,
      title: 'PosEx',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    await AppDiagnostics.log('INFO', 'Window manager ready (close guarded)');
  }

  /// Creates WebView2 environment before the widget tree mounts so failures
  /// show an error panel instead of a silent native crash.
  static Future<String?> prepareWebViewEnvironment() async {
    if (!Platform.isWindows) return null;

    try {
      sharedWebViewEnvironment = await _createWebViewEnvironment(
        resetProfile: false,
      );
      await AppDiagnostics.log('INFO', 'WebView2 environment ready');
      return null;
    } catch (e, st) {
      await AppDiagnostics.logError('WebView2 environment failed', e, st);
    }

    try {
      sharedWebViewEnvironment = await _createWebViewEnvironment(
        resetProfile: true,
      );
      await AppDiagnostics.log('INFO', 'WebView2 environment ready after profile reset');
      return null;
    } catch (e, st) {
      await AppDiagnostics.logError(
        'WebView2 environment failed after profile reset',
        e,
        st,
      );
      return 'WebView2 failed to start: $e\n\n'
          'Try: close PosEx, delete the webview2 folder under '
          '%APPDATA%\\posex_app\\, then open PosEx again.';
    }
  }

  static Future<WebViewEnvironment> _createWebViewEnvironment({
    required bool resetProfile,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final userData = Directory('${dir.path}${Platform.pathSeparator}webview2');
    if (resetProfile && userData.existsSync()) {
      await userData.delete(recursive: true);
    }

    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: userData.path,
      ),
    );
  }
}
