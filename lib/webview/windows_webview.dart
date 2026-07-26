import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_win_floating/webview_win_floating.dart';

import '../platform/app_diagnostics.dart';
import '../platform/windows_startup.dart';

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
  WinWebViewController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    try {
      // Must be AppData — Program Files installs cannot write next to the exe.
      final userDataFolder = await WindowsStartup.ensureWebView2UserDataFolder();
      await AppDiagnostics.log(
        'INFO',
        'Windows WebView userDataFolder: $userDataFolder',
      );

      final controller = WinWebViewController(
        params: WindowsWebViewControllerCreationParams(
          userDataFolder: userDataFolder,
        ),
      );
      _controller = controller;
      if (mounted) setState(() {});

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      await controller.addJavaScriptChannel(
        'PosExNativeBridgeChannel',
        onMessageReceived: (JavaScriptMessage message) {
          widget.onBridgeMessage(message.message);
        },
      );

      await controller.setNavigationDelegate(
        WinNavigationDelegate(
          onPageStarted: (url) async {
            widget.onLoadingChanged(true);
            await controller.runJavaScript('''
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

      await controller.loadRequest(Uri.parse(widget.url));

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
          _errorMsg =
              'WebView failed to start: $e\n\n'
              'If PosEx is installed under Program Files, update to the latest build.\n'
              'Or delete %APPDATA%\\posex_app\\webview2 and try again.';
        });
      }
      widget.onLoadFailed(e.toString());
    }
  }

  Future<void> runJavaScript(String js) async {
    final controller = _controller;
    if (!_initialized || controller == null) return;
    try {
      await controller.runJavaScript(js);
    } catch (e, st) {
      await AppDiagnostics.logError('Windows WebView JS execution failed', e, st);
    }
  }

  Future<bool> canGoBack() async {
    final controller = _controller;
    if (!_initialized || controller == null) return false;
    try {
      return await controller.canGoBack();
    } catch (_) {
      return false;
    }
  }

  Future<void> goBack() async {
    final controller = _controller;
    if (!_initialized || controller == null) return;
    try {
      await controller.goBack();
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

    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }

    // Mount the platform view immediately so HWND/bounds attach (plugin example).
    return Stack(
      fit: StackFit.expand,
      children: [
        WinWebViewWidget(controller: controller),
        if (!_initialized)
          const ColoredBox(
            color: Color(0xFF0B1220),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFF97316)),
            ),
          ),
      ],
    );
  }

}
