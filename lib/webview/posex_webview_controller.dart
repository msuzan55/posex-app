import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebFileSelectorParams {
  WebFileSelectorParams({required this.isCaptureEnabled});

  final bool isCaptureEnabled;
}

/// Cross-platform WebView wrapper via flutter_inappwebview.
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
  final Future<List<String>> Function(WebFileSelectorParams params)
      onShowFileSelector;

  InAppWebViewController? _controller;
  bool _canGoBack = false;
  bool _ready = false;
  String? _initialUrl;

  bool get isReady {
    return _ready;
  }

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
      onLoadStart: (_, __) => onLoadingChanged(true),
      onLoadStop: (_, __) async {
        onLoadingChanged(false);
        _canGoBack = await _controller?.canGoBack() ?? false;
        onPageFinished();
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame ?? false) {
          debugPrint('[WebView] ${error.code} ${error.description}');
        }
      },
      onPermissionRequest: (_, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      androidOnShowFileChooser: (_, params) async {
        final files = await onShowFileSelector(
          WebFileSelectorParams(isCaptureEnabled: params.isCaptureEnabled),
        );
        return FileChooserResponse(
          filePaths: files
              .map((f) {
                if (f.startsWith('file://')) return f.substring(7);
                return f;
              })
              .toList(),
          handledByClient: true,
        );
      },
      onUpdateVisitedHistory: (_, __, ___, ____) async {
        _canGoBack = await _controller?.canGoBack() ?? false;
      },
    );
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
