import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

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
  String? _initialUrl;

  bool get isReady => _ready;

  Future<void> initialize(String initialUrl) async {
    if (Platform.isWindows) {
      await _ensureWindowsEnvironment();
    }
    _initialUrl = initialUrl;
    _ready = true;
  }

  Future<void> _ensureWindowsEnvironment() async {
    if (_windowsEnv != null) return;

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
    if (!_ready || _initialUrl == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }
    return InAppWebView(
      webViewEnvironment: _windowsEnv,
      initialUrlRequest: URLRequest(url: WebUri(_initialUrl!)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: false,
        transparentBackground: false,
        disableDefaultErrorPage: false,
        useHybridComposition: Platform.isAndroid,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: '''
(function(){
  document.documentElement.classList.add('posex-native-app');
  document.documentElement.style.setProperty('--safe-top', '0px');
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
        controller.addJavaScriptHandler(
          handlerName: 'PosExNativeBridge',
          callback: (args) {
            if (args.isEmpty) return;
            onBridgeMessage('${args.first}');
          },
        );
      },
      onLoadStart: (controller, url) {
        _pageLoaded = false;
        onLoadingChanged(true);
      },
      onLoadStop: (controller, url) {
        _markPageLoaded();
      },
      onProgressChanged: (controller, progress) {
        if (progress >= 100) {
          _markPageLoaded();
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          debugPrint('[WebView] ${error.type} ${error.description}');
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
    _initialUrl = null;
    _pageLoaded = false;
  }
}
