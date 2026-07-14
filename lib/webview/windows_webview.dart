import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_win_floating/webview_win_floating.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import '../platform/app_diagnostics.dart';

class WindowsWebView extends StatefulWidget {
  const WindowsWebView({
    super.key,
    required this.url,
    required this.onBridgeMessage,
    required this.onPageFinished,
    required this.onLoadingChanged,
    required this.onLoadFailed,
  });

  final String url;
  final void Function(String message) onBridgeMessage;
  final VoidCallback onPageFinished;
  final void Function(bool loading) onLoadingChanged;
  final void Function(String message) onLoadFailed;

  @override
  State<WindowsWebView> createState() => WindowsWebViewState();
}

class WindowsWebViewState extends State<WindowsWebView> {
  late final WinWebViewController _controller;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _controller = WinWebViewController();
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      // Listen for messages from JavaScript
      await _controller.addJavaScriptChannel(
        'PosExNativeBridgeChannel',
        onMessageReceived: (JavaScriptMessage message) {
          widget.onBridgeMessage(message.message);
        },
      );

      // Listen for page events
      await _controller.setNavigationDelegate(
        WinNavigationDelegate(
          onPageStarted: (url) async {
            widget.onLoadingChanged(true);
            // Inject native bridge and CSS settings when loading starts
            await _controller.runJavaScript('''
(function(){
  document.documentElement.classList.add('posex-native-app');
  document.documentElement.style.setProperty('--safe-top', '0px');
  document.documentElement.style.setProperty('--safe-bottom', '0px');
  
  window.PosExNativeBridge = window.PosExNativeBridge || {
    postMessage: function(m){
      try {
        PosExNativeBridgeChannel.postMessage(String(m));
      } catch(e) {
        console.error('Bridge postMessage failed', e);
      }
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
''');
          },
          onPageFinished: (url) async {
            widget.onLoadingChanged(false);
            widget.onPageFinished();
          },
          onWebResourceError: (error) {
            widget.onLoadFailed(error.description);
          },
        ),
      );

      await _controller.loadRequest(Uri.parse(widget.url));

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e, st) {
      await AppDiagnostics.logError('Windows WebView initialization failed', e, st);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = e.toString();
        });
      }
      widget.onLoadFailed(e.toString());
    }
  }

  Future<void> runJavaScript(String js) async {
    if (!_initialized) return;
    try {
      await _controller.runJavaScript(js);
    } catch (e, st) {
      await AppDiagnostics.logError('Windows WebView JS execution failed', e, st);
    }
  }

  /// Hide/show the native Windows WebView HWND. Required before any Flutter
  /// route overlays (widgets cannot draw above the WebView).
  Future<void> setVisible(bool visible) async {
    if (!_initialized) return;
    try {
      await _controller.setVisibility(visible);
    } catch (e, st) {
      await AppDiagnostics.logError('Windows WebView setVisibility failed', e, st);
    }
  }

  Future<bool> canGoBack() async {
    if (!_initialized) return false;
    try {
      return await _controller.canGoBack();
    } catch (_) {
      return false;
    }
  }

  Future<void> goBack() async {
    if (!_initialized) return;
    try {
      await _controller.goBack();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMsg ?? 'WebView Error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }

    return WinWebViewWidget(controller: _controller);
  }
}
