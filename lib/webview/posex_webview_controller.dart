import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/app_diagnostics.dart';
import '../platform/windows_startup.dart';

/// Cross-platform WebView wrapper via flutter_inappwebview.
class PosexWebViewController {
  PosexWebViewController({
    required this.onBridgeMessage,
    required this.onPageFinished,
    required this.onLoadingChanged,
    this.onLoadFailed,
  });

  final void Function(String message) onBridgeMessage;
  final VoidCallback onPageFinished;
  final void Function(bool loading) onLoadingChanged;
  final void Function(String message)? onLoadFailed;

  InAppWebViewController? _controller;
  WebViewEnvironment? _windowsEnv;
  bool _canGoBack = false;
  bool _ready = false;
  bool _pageLoaded = false;
  bool _mountWebView = false;
  String? _initialUrl;

  bool get isReady => _ready;

  Future<void> initialize(String initialUrl) async {
    if (Platform.isWindows) {
      await _ensureWindowsEnvironment();
    }
    _initialUrl = initialUrl;
    _ready = true;
    _mountWebView = !Platform.isWindows;
    if (Platform.isWindows) {
      // Let the shell paint once before creating the native WebView2 control.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _mountWebView = true;
      await AppDiagnostics.log('INFO', 'WebView widget mount enabled');
    }
  }

  Future<void> _ensureWindowsEnvironment() async {
    if (_windowsEnv != null) return;

    final shared = WindowsStartup.sharedWebViewEnvironment;
    if (shared != null) {
      _windowsEnv = shared;
      return;
    }

    final runtimeVersion = await WebViewEnvironment.getAvailableVersion();
    if (runtimeVersion == null) {
      throw StateError(
        'WebView2 runtime not found. Install Microsoft Edge WebView2 Runtime.',
      );
    }

    final dir = await getApplicationSupportDirectory();
    final userData = '${dir.path}${Platform.pathSeparator}webview2';
    _windowsEnv = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: userData),
    );
  }

  Widget buildWidget() {
    if (!_ready || _initialUrl == null || !_mountWebView) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }
    return InAppWebView(
      webViewEnvironment: _windowsEnv,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: false,
        transparentBackground: false,
        disableDefaultErrorPage: false,
        useHybridComposition: Platform.isAndroid,
        hardwareAcceleration: !Platform.isWindows,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: false,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        return NavigationActionPolicy.ALLOW;
      },
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: '''
(function(){
  document.documentElement.classList.add('posex-native-app');
  document.documentElement.style.setProperty('--safe-top', '0px');
  document.documentElement.style.setProperty('--safe-bottom', '0px');
  window.PosExNativeBridge = window.PosExNativeBridge || {
    postMessage: function(m){
      window.flutter_inappwebview.callHandler('PosExNativeBridge', String(m));
    }
  };
})();
''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        unawaited(AppDiagnostics.log('INFO', 'InAppWebView control created'));
        controller.addJavaScriptHandler(
          handlerName: 'PosExNativeBridge',
          callback: (args) {
            if (args.isEmpty) return;
            onBridgeMessage('${args.first}');
          },
        );
        final url = _initialUrl;
        if (url != null && url.isNotEmpty) {
          unawaited(() async {
            try {
              await AppDiagnostics.log('INFO', 'Loading PosEx URL: $url');
              await controller.loadUrl(
                urlRequest: URLRequest(url: WebUri(url)),
              );
            } catch (e, st) {
              await AppDiagnostics.logError('WebView loadUrl failed', e, st);
              onLoadFailed?.call('$e');
            }
          }());
        }
      },
      onLoadStart: (controller, url) {
        _pageLoaded = false;
        onLoadingChanged(true);
      },
      onLoadStop: (controller, url) {
        if (_isAppUrl(url)) {
          _markPageLoaded();
        }
      },
      onProgressChanged: (controller, progress) {
        if (progress >= 100) {
          unawaited(() async {
            final url = await controller.getUrl();
            if (_isAppUrl(url)) {
              _markPageLoaded();
            }
          }());
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          final detail = '${error.type} ${error.description}';
          unawaited(AppDiagnostics.log('WEBVIEW', 'Main frame error: $detail'));
          onLoadFailed?.call(error.description);
          onLoadingChanged(false);
        }
      },
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        unawaited(_refreshCanGoBack());
      },
    );
  }

  void _markPageLoaded() {
    if (_pageLoaded) return;
    _pageLoaded = true;
    onLoadingChanged(false);
    unawaited(_refreshCanGoBack());
    onPageFinished();
  }

  bool _isAppUrl(WebUri? url) {
    final value = url?.toString() ?? '';
    if (value.isEmpty || value.startsWith('about:')) return false;
    return value.contains('posex.lk');
  }

  Future<void> _refreshCanGoBack() async {
    _canGoBack = await _controller?.canGoBack() ?? false;
  }

  Future<void> runJavaScript(String js) async {
    await _controller?.evaluateJavascript(source: js);
  }

  Future<bool> canGoBack() async {
    _canGoBack = await _controller?.canGoBack() ?? _canGoBack;
    return _canGoBack;
  }

  Future<void> goBack() async {
    await _controller?.goBack();
  }

  Future<void> dispose() async {
    _controller = null;
    _ready = false;
    _mountWebView = false;
    _initialUrl = null;
    _pageLoaded = false;
  }
}
