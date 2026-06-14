import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cross-platform WebView wrapper via flutter_inappwebview.
class PosexWebViewController {
  PosexWebViewController({
    required this.onBridgeMessage,
    required this.onPageFinished,
    required this.onLoadingChanged,
  });

  final void Function(String message) onBridgeMessage;
  final VoidCallback onPageFinished;
  final void Function(bool loading) onLoadingChanged;

  InAppWebViewController? _controller;
  bool _canGoBack = false;
  bool _ready = false;
  String? _initialUrl;

  bool get isReady => _ready;

  Future<void> initialize(String initialUrl) async {
    _initialUrl = initialUrl;
    _ready = true;
  }

  Widget buildWidget() {
    if (!_ready || _initialUrl == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_initialUrl!)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportZoom: false,
        transparentBackground: false,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: '''
window.PosExNativeBridge = window.PosExNativeBridge || {
  postMessage: function(m){
    window.flutter_inappwebview.callHandler('PosExNativeBridge', String(m));
  }
};
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
      onLoadStart: (controller, url) => onLoadingChanged(true),
      onLoadStop: (controller, url) {
        onLoadingChanged(false);
        unawaited(_refreshCanGoBack());
        onPageFinished();
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          debugPrint('[WebView] ${error.type} ${error.description}');
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
  }
}
