import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../platform/app_diagnostics.dart';
import '../platform/native_file_bridge.dart';
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
        useOnDownloadStart: Platform.isAndroid,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        return NavigationActionPolicy.ALLOW;
      },
      onDownloadStartRequest: (controller, request) async {
        if (!Platform.isAndroid) return;
        unawaited(_handleHttpDownload(request));
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
          source: _bridgeBootstrapJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        if (Platform.isAndroid)
          UserScript(
            source: _androidShareDownloadPolyfillJs,
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
        if (Platform.isAndroid) {
          controller.addJavaScriptHandler(
            handlerName: 'PosExShareFile',
            callback: (args) async {
              final map = _firstArgMap(args);
              return NativeFileBridge.shareFile(
                base64: '${map['base64'] ?? ''}',
                fileName: '${map['fileName'] ?? 'share.bin'}',
                mimeType: '${map['mimeType'] ?? 'application/octet-stream'}',
                title: '${map['title'] ?? ''}',
                text: '${map['text'] ?? ''}',
              );
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'PosExSaveFile',
            callback: (args) async {
              final map = _firstArgMap(args);
              return NativeFileBridge.saveFile(
                base64: '${map['base64'] ?? ''}',
                fileName: '${map['fileName'] ?? 'download.bin'}',
                mimeType: '${map['mimeType'] ?? 'application/octet-stream'}',
              );
            },
          );
        }
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

  static Map<String, dynamic> _firstArgMap(List<dynamic> args) {
    if (args.isEmpty) return <String, dynamic>{};
    final first = args.first;
    if (first is Map) {
      return Map<String, dynamic>.from(first);
    }
    return <String, dynamic>{};
  }

  Future<void> _handleHttpDownload(DownloadStartRequest request) async {
    final url = request.url.toString();
    if (url.isEmpty || url.startsWith('blob:') || url.startsWith('data:')) {
      return;
    }
    try {
      await AppDiagnostics.log('INFO', 'WebView download: $url');
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Download failed (${resp.statusCode})');
      }
      final suggested = (request.suggestedFilename ?? '').trim();
      final fileName = suggested.isNotEmpty
          ? suggested
          : _fileNameFromUrl(url, request.mimeType);
      final mime = (request.mimeType ?? '').trim().isNotEmpty
          ? request.mimeType!.trim()
          : (resp.headers['content-type']?.split(';').first.trim() ??
              'application/octet-stream');
      final result = await NativeFileBridge.saveFile(
        base64: base64Encode(resp.bodyBytes),
        fileName: fileName,
        mimeType: mime,
      );
      if (result['ok'] != true) {
        throw Exception('${result['error'] ?? 'Save failed'}');
      }
    } catch (e, st) {
      await AppDiagnostics.logError('WebView download failed', e, st);
    }
  }

  static String _fileNameFromUrl(String url, String? mimeType) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isNotEmpty && path.last.contains('.')) {
        return path.last;
      }
    } catch (_) {}
    if ((mimeType ?? '').contains('pdf')) return 'download.pdf';
    return 'download.bin';
  }

  static const String _bridgeBootstrapJs = r'''
(function(){
  document.documentElement.classList.add('posex-native-app');
  document.documentElement.style.setProperty('--safe-top', '0px');
  document.documentElement.style.setProperty('--safe-bottom', '0px');
  window.PosExNativeBridge = window.PosExNativeBridge || {};
  if (!window.PosExNativeBridge.postMessage) {
    window.PosExNativeBridge.postMessage = function(m){
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
    };
  }
  var nativeClose = window.close;
  window.close = function(){
    try{
      console.warn('[PosEx] blocked window.close() in native app');
    }catch(e){}
  };
  window.__posexNativeClose = nativeClose;
})();
''';

  /// Android WebView lacks Web Share file support and blob `<a download>`.
  /// Route both through native FileProvider / MediaStore.
  static const String _androidShareDownloadPolyfillJs = r'''
(function(){
  if (window.__posexFileBridgeInstalled) return;
  window.__posexFileBridgeInstalled = true;

  function waitForHandler(name, payload) {
    return new Promise(function(resolve, reject) {
      var attempts = 0;
      function tryCall() {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler(name, payload).then(resolve).catch(reject);
          return;
        }
        if (attempts >= 50) {
          reject(new Error('Native bridge not ready'));
          return;
        }
        attempts++;
        setTimeout(tryCall, 100);
      }
      tryCall();
    });
  }

  function blobToBase64(blob) {
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onload = function() {
        var s = String(reader.result || '');
        var i = s.indexOf(',');
        resolve(i >= 0 ? s.slice(i + 1) : s);
      };
      reader.onerror = function() { reject(reader.error || new Error('read failed')); };
      reader.readAsDataURL(blob);
    });
  }

  async function nativeShareFile(opts) {
    var result = await waitForHandler('PosExShareFile', opts || {});
    if (result && result.ok === false) {
      throw new Error(result.error || 'Share failed');
    }
    return result;
  }

  async function nativeSaveFile(opts) {
    var result = await waitForHandler('PosExSaveFile', opts || {});
    if (result && result.ok === false) {
      throw new Error(result.error || 'Save failed');
    }
    return result;
  }

  window.PosExNativeBridge = window.PosExNativeBridge || {};
  window.PosExNativeBridge.shareFile = nativeShareFile;
  window.PosExNativeBridge.saveFile = nativeSaveFile;
  window.PosExNativeBridge.supportsFileShare = true;
  window.PosExNativeBridge.supportsFileSave = true;

  var origShare = (typeof navigator.share === 'function')
    ? navigator.share.bind(navigator)
    : null;

  navigator.canShare = function(data) {
    if (!data) return true;
    if (data.files && data.files.length) return true;
    return true;
  };

  navigator.share = async function(data) {
    data = data || {};
    if (data.files && data.files.length) {
      var file = data.files[0];
      var b64 = await blobToBase64(file);
      return nativeShareFile({
        base64: b64,
        fileName: file.name || 'share.bin',
        mimeType: file.type || 'application/octet-stream',
        title: data.title || '',
        text: data.text || ''
      });
    }
    if (data.text || data.url || data.title) {
      return nativeShareFile({
        base64: '',
        fileName: '',
        mimeType: 'text/plain',
        title: data.title || '',
        text: data.text || data.url || ''
      });
    }
    if (origShare) return origShare(data);
    throw new Error('Nothing to share');
  };

  document.addEventListener('click', function(e) {
    var a = e.target && e.target.closest ? e.target.closest('a[download]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href.indexOf('blob:') !== 0 && href.indexOf('data:') !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    var fileName = a.getAttribute('download') || 'download.bin';
    (async function() {
      var blob = await fetch(href).then(function(r) { return r.blob(); });
      var b64 = await blobToBase64(blob);
      await nativeSaveFile({
        base64: b64,
        fileName: fileName,
        mimeType: blob.type || 'application/octet-stream'
      });
    })().catch(function(err) {
      console.error('[PosEx] native save failed', err);
      try {
        alert('Could not save file: ' + ((err && err.message) || err));
      } catch (_) {}
    });
  }, true);
})();
''';
}
