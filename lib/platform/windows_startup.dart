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

  static Future<String?> checkRuntimeRequirements() async {
    if (!Platform.isWindows) return null;

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

  static Future<void> setupWindow() async {
    if (!Platform.isWindows) return;

    await windowManager.ensureInitialized();

    Future<void> showWindow() async {
      await windowManager.show();
      await windowManager.focus();
    }

    const hiddenOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: 'PosEx',
      titleBarStyle: TitleBarStyle.hidden,
    );
    const normalOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      title: 'PosEx',
      titleBarStyle: TitleBarStyle.normal,
    );

    try {
      windowManager.waitUntilReadyToShow(hiddenOptions, showWindow);
      await AppDiagnostics.log('INFO', 'Window manager ready (hidden title bar)');
    } catch (e, st) {
      await AppDiagnostics.logError(
        'Hidden title bar failed, using normal title bar',
        e,
        st,
      );
      windowManager.waitUntilReadyToShow(normalOptions, showWindow);
      await AppDiagnostics.log('INFO', 'Window manager ready (normal title bar)');
    }
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
      settings: WebViewEnvironmentSettings(userDataFolder: userData.path),
    );
  }
}
