import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as win;

const _bridgeShim = r'''
(function(){
  if(window.PosExNativeBridge) return;
  if(window.chrome&&window.chrome.webview){
    window.PosExNativeBridge={
      postMessage:function(m){
        window.chrome.webview.postMessage(typeof m==='string'?m:String(m));
      }
    };
  }
})();
''';

/// Cross-platform WebView wrapper (Android: webview_flutter, Windows: WebView2).
class PosexWebViewController {
  PosexWebViewController({
    required this.onBridgeMessage,
    required this.onPageFinished,
    required this.onLoadingChanged,
    required this.onShowFileSelector,
  });

  final void Function(String message) onBridgeMessage;
  final VoidCallback onPageFinished;
  final void Function(bool loading) onLoadingChanged;
  final Future<List<String>> Function(FileSelectorParams params)
      onShowFileSelector;

  WebViewController? _android;
  win.WebviewController? _windows;
  bool _canGoBack = false;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool get isReady {
    if (Platform.isWindows) {
      return _windows?.value.isInitialized == true;
    }
    return _android != null;
  }

  Future<void> initialize(String initialUrl) async {
    if (Platform.isWindows) {
      await _initWindows(initialUrl);
    } else {
      await _initAndroid(initialUrl);
    }
  }

  Future<void> _initAndroid(String initialUrl) async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'PosExNativeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          onBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => onLoadingChanged(true),
          onPageFinished: (_) {
            onLoadingChanged(false);
            onPageFinished();
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] ${error.errorCode} ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setMixedContentMode(MixedContentMode.alwaysAllow);
      platform.setOnShowFileSelector(onShowFileSelector);
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }

    _android = controller;
  }

  Future<void> _initWindows(String initialUrl) async {
    final controller = win.WebviewController();
    _windows = controller;

    try {
      await controller.initialize();
      await controller.setBackgroundColor(Colors.black);
      await controller.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      await controller.addScriptToExecuteOnDocumentCreated(_bridgeShim);

      _subscriptions
        ..add(controller.loadingState.listen((state) {
          onLoadingChanged(state == win.LoadingState.loading);
          if (state == win.LoadingState.navigationCompleted) {
            onPageFinished();
          }
        }))
        ..add(controller.historyChanged.listen((history) {
          _canGoBack = history.canGoBack;
        }))
        ..add(controller.webMessage.listen((message) {
          if (message is String) {
            onBridgeMessage(message);
          } else if (message != null) {
            onBridgeMessage(message.toString());
          }
        }));

      await controller.loadUrl(initialUrl);
    } on PlatformException catch (e) {
      debugPrint('[WebView] Windows init failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  Widget buildWidget() {
    if (Platform.isWindows) {
      final controller = _windows;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFF97316)),
        );
      }
      return win.Webview(
        controller,
        permissionRequested: (url, kind, initiated) async {
          return win.WebviewPermissionDecision.allow;
        },
      );
    }

    final controller = _android;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }
    return WebViewWidget(controller: controller);
  }

  Future<void> runJavaScript(String js) async {
    if (Platform.isWindows) {
      await _windows?.executeScript(js);
      return;
    }
    await _android?.runJavaScript(js);
  }

  Future<bool> canGoBack() async {
    if (Platform.isWindows) return _canGoBack;
    return _android?.canGoBack() ?? false;
  }

  Future<void> goBack() async {
    if (Platform.isWindows) {
      await _windows?.goBack();
      return;
    }
    await _android?.goBack();
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _windows?.dispose();
    _windows = null;
    _android = null;
  }
}
