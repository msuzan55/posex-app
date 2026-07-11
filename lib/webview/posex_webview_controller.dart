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
    this.onRenderProcessGone,
  });

  final void Function(String message) onBridgeMessage;
  final VoidCallback onPageFinished;
  final void Function(bool loading) onLoadingChanged;
  final void Function(String message)? onLoadFailed;
  final void Function(bool didCrash)? onRenderProcessGone;

  static const _webViewKey = ValueKey<String>('posex-main-webview');

  final InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  final Completer<void> _mountReady = Completer<void>();

  InAppWebViewController? _controller;
  WebViewEnvironment? _windowsEnv;
  Widget? _stableWebViewWidget;
  bool _widgetBuilt = false;
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
    if (Platform.isWindows) {
      // Let the native window finish showing before embedding WebView2.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AppDiagnostics.log('INFO', 'WebView widget mount enabled');
    }
    if (!_mountReady.isCompleted) {
      _mountReady.complete();
    }
  }

  /// Waits until [initialize] has finished and the host may mount the widget.
  Future<void> waitUntilMountable() async {
    await _mountReady.future;
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

  /// Builds the platform WebView widget exactly once for [StableWebViewHost].
  Widget buildWidgetOnce() {
    if (_widgetBuilt) {
      return _stableWebViewWidget!;
    }
    if (!_ready || _initialUrl == null) {
      throw StateError('WebView controller is not ready');
    }

    _widgetBuilt = true;
    _stableWebViewWidget = InAppWebView(
      key: _webViewKey,
      keepAlive: _keepAlive,
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
        hardwareAcceleration: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: false,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        await AppDiagnostics.log(
          'INFO',
          'WebView popup blocked, loading in place: $url',
        );
        if (url.isNotEmpty) {
          await controller.loadUrl(urlRequest: action.request);
        }
        return false;
      },
      onCloseWindow: (controller) {
        unawaited(
          AppDiagnostics.log(
            'WARN',
            'WebView window.close() ignored — PosEx stays open',
          ),
        );
      },
      onRenderProcessGone: (controller, detail) {
        unawaited(() async {
          final crashed = detail.didCrash;
          await AppDiagnostics.log(
            'ERROR',
            'WebView render process gone: ${crashed ? 'crashed' : 'terminated'}',
          );
          await AppDiagnostics.logStartupFailure(
            'WebView ${crashed ? 'crashed' : 'stopped'}. Reloading PosEx…',
          );
          onRenderProcessGone?.call(crashed);
          try {
            await controller.reload();
            await AppDiagnostics.log('INFO', 'WebView reload after render process exit');
          } catch (e, st) {
            await AppDiagnostics.logError('WebView reload failed', e, st);
          }
        }());
      },
      onConsoleMessage: (controller, message) {
        if (message.messageLevel == ConsoleMessageLevel.ERROR) {
          unawaited(
            AppDiagnostics.log('WEBVIEW', 'JS error: ${message.message}'),
          );
        }
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
      var attempts = 0;
      function send() {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('PosExNativeBridge', String(m));
        } else if (attempts < 50) {
          attempts++;
          setTimeout(send, 100);
        }
      }
      send();
    }
  };
  var nativeClose = window.close;
  window.close = function(){
    try{
      console.warn('[PosEx] blocked window.close() in native app');
    }catch(e){}
  };
  window.__posexNativeClose = nativeClose;
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
      },
      onLoadStart: (controller, url) {
        _pageLoaded = false;
        onLoadingChanged(true);
        unawaited(AppDiagnostics.log('INFO', 'WebView load start: $url'));
      },
      onLoadStop: (controller, url) {
        unawaited(AppDiagnostics.log('INFO', 'WebView load stop: $url'));
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

    return _stableWebViewWidget!;
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
    if (_widgetBuilt) {
      try {
        await InAppWebViewController.disposeKeepAlive(_keepAlive);
      } catch (_) {}
    }
    _stableWebViewWidget = null;
    _widgetBuilt = false;
    _ready = false;
    _initialUrl = null;
    _pageLoaded = false;
  }
}
