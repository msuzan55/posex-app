import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
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
  final WebviewController _controller = WebviewController();
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
      final runtimeVersion = await WebviewController.getWebViewVersion();
      if (runtimeVersion == null) {
        throw StateError(
          'Microsoft Edge WebView2 Runtime is not installed.\n\n'
          'Please install it, then restart PosEx.',
        );
      }

      await _controller.initialize();

      // Inject native bridge and CSS settings on document creation
      await _controller.addScriptToExecuteOnDocumentCreated('''
(function(){
  document.documentElement.classList.add('posex-native-app');
  document.documentElement.style.setProperty('--safe-top', '0px');
  document.documentElement.style.setProperty('--safe-bottom', '0px');
  
  window.PosExNativeBridge = window.PosExNativeBridge || {
    postMessage: function(m){
      window.chrome.webview.postMessage(String(m));
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

      // Listen for messages from JavaScript
      _controller.webMessage.listen((dynamic message) {
        if (message != null) {
          widget.onBridgeMessage(message.toString());
        }
      });

      // Listen for loading state changes
      _controller.loadingState.listen((state) {
        if (state == LoadingState.loading) {
          widget.onLoadingChanged(true);
        } else if (state == LoadingState.navigationCompleted) {
          widget.onLoadingChanged(false);
          widget.onPageFinished();
        }
      });

      await _controller.loadUrl(widget.url);

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
      await _controller.executeScript(js);
    } catch (e, st) {
      await AppDiagnostics.logError('Windows WebView JS execution failed', e, st);
    }
  }

  Future<bool> canGoBack() async {
    if (!_initialized) return false;
    try {
      final res = await _controller.executeScript('window.history.length > 1');
      return res == true || res == 1 || res == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> goBack() async {
    if (!_initialized) return;
    try {
      await _controller.executeScript('window.history.back()');
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

    return Webview(_controller);
  }
}
