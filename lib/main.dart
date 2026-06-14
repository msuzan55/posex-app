import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'platform/app_permissions.dart';
import 'print_server/device_info_service.dart';
import 'print_server/print_foreground_service.dart';
import 'print_server/print_http_server.dart';
import 'print_server/print_server_panel.dart';
import 'print_server/printer_manager.dart';
import 'print_server/printer_store.dart';
import 'push/push_registration_service.dart';
import 'update/update_service.dart';
import 'update/windows_install_paths.dart';
import 'webview/posex_webview_controller.dart';

/// PosEx standalone app — WebView wrapper around the PosEx web app, with an
/// embedded localhost print server (USB/Bluetooth/Network) on :9753.
const String kPosexUrl = 'https://posex.lk/test/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Visible but transparent status bar (not full-screen / immersive).
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PosexApp());
}

class PosexApp extends StatelessWidget {
  const PosexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PosEx',
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  PosexWebViewController? _webView;
  PrinterManager? _printerManager;
  PrintHttpServer? _printServer;
  final UpdateService _updateService = UpdateService();

  bool _loading = true;
  bool _webReady = false;
  bool _showPrintFab = true;
  String? _bootstrapError;
  Timer? _fabTimer;
  Timer? _probeTimer;
  VoidCallback? _printerManagerListener;
  UpdateInfo? _update;
  UpdateDownloadState _updateState = UpdateDownloadState.idle;
  double _downloadProgress = 0;
  String? _updateError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
    _bootstrap();

    _fabTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showPrintFab = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabTimer?.cancel();
    _probeTimer?.cancel();
    final listener = _printerManagerListener;
    final manager = _printerManager;
    if (listener != null && manager != null) {
      manager.removeListener(listener);
    }
    unawaited(_webView?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_nudgeWebAppSync());
    }
    // Keep background remote printing alive only while printers are connected.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_syncPrintForegroundService());
    }
  }

  /// Wake WebSocket + sync when the native shell returns to foreground (Windows has no Android foreground service).
  Future<void> _nudgeWebAppSync() async {
    final webView = _webView;
    if (webView == null) return;
    try {
      await webView.runJavaScript('''
(function(){
  try{
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('focus'));
  }catch(e){}
})();
''');
    } catch (_) {}
  }

  Future<void> _syncPrintForegroundService() async {
    if (!Platform.isAndroid) return;
    final manager = _printerManager;
    if (manager == null) return;

    if (!manager.hasConnectedPrinter) {
      await PrintForegroundService.stop();
      return;
    }

    final notif = await Permission.notification.status;
    if (!notif.isGranted) return;

    await PrintForegroundService.start(
      connectedCount: manager.connectedPrinterCount,
    );
  }

  void _attachPrinterManagerListener(PrinterManager manager) {
    _printerManagerListener ??= () {
      unawaited(_syncPrintForegroundService());
    };
    manager.removeListener(_printerManagerListener!);
    manager.addListener(_printerManagerListener!);
  }

  Future<void> _bootstrap() async {
    try {
      await _requestPermissions();

      final manager = PrinterManager(PrinterStore());
      final server = PrintHttpServer(manager);
      _printerManager = manager;
      _printServer = server;

      await DeviceInfoService.deviceName();

      if (Platform.isWindows) {
        await WindowsInstallPaths.rememberCurrentInstallDir();
      }

      unawaited(PushRegistrationService.init());

      final printStarted = await server.start();
      if (!printStarted) {
        _bootstrapError = 'Print server could not start on port ${PrintHttpServer.port}';
      }

      await manager.init();
      _attachPrinterManagerListener(manager);

      _probeTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await manager.reconnectAll();
        await _syncPrintForegroundService();
      });

      await _syncPrintForegroundService();
    } catch (e, st) {
      debugPrint('[PosEx] bootstrap error: $e\n$st');
      _bootstrapError ??= 'Startup error: $e';
    } finally {
      if (mounted) {
        setState(() {});
        _checkForUpdate();
      }
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await _updateService.checkForUpdate();
    if (!mounted || info == null) return;

    setState(() {
      _update = info;
      _updateError = null;
    });

    if (await _updateService.isDownloadReady(info)) {
      if (mounted) {
        setState(() => _updateState = UpdateDownloadState.ready);
      }
      return;
    }

    await _downloadUpdate(info);
  }

  Future<void> _downloadUpdate(UpdateInfo info) async {
    if (_updateState == UpdateDownloadState.downloading) return;

    setState(() {
      _updateState = UpdateDownloadState.downloading;
      _downloadProgress = 0;
      _updateError = null;
    });

    try {
      await _updateService.downloadUpdate(
        info,
        onProgress: (p) {
          if (mounted) {
            setState(() => _downloadProgress = p);
          }
        },
      );
      if (mounted) {
        setState(() => _updateState = UpdateDownloadState.ready);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateState = UpdateDownloadState.failed;
          _updateError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _runUpdate() async {
    final info = _update;
    if (info == null) return;

    if (_updateState == UpdateDownloadState.ready) {
      setState(() => _updateError = null);
      try {
        await _updateService.installDownloadedUpdate();
      } on PlatformException catch (e) {
        if (mounted) {
          setState(() {
            _updateState = UpdateDownloadState.failed;
            _updateError = e.message ?? 'Install failed';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _updateState = UpdateDownloadState.failed;
            _updateError = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
      return;
    }

    if (_updateState == UpdateDownloadState.downloading) return;

    await _downloadUpdate(info);
  }

  String _updateBannerText() {
    final info = _update;
    if (info == null) return '';

    switch (_updateState) {
      case UpdateDownloadState.downloading:
        return 'Downloading update… ${(_downloadProgress * 100).toStringAsFixed(0)}%';
      case UpdateDownloadState.ready:
        return Platform.isWindows
            ? 'Update ready — tap to restart now'
            : 'Update ready — tap to install now';
      case UpdateDownloadState.failed:
        return _updateError == null || _updateError!.isEmpty
            ? 'Update failed — tap to retry'
            : 'Update failed — tap to retry';
      case UpdateDownloadState.idle:
        return 'Update available — preparing download…';
    }
  }

  /// Camera + photo/storage so product-photo capture and gallery upload work.
  Future<void> _requestPermissions() async {
    await requestAppPermissions();
  }

  void _initWebView() {
    final webView = PosexWebViewController(
      onBridgeMessage: _onBridgeMessage,
      onPageFinished: () {
        _syncAuthTokenFromWebView();
        _reportNativePushStatus();
      },
      onLoadingChanged: (loading) {
        if (mounted) setState(() => _loading = loading);
      },
      onShowFileSelector: _onShowFileSelector,
    );
    _webView = webView;
    unawaited(() async {
      try {
        await webView.initialize(kPosexUrl);
      } catch (e, st) {
        debugPrint('[PosEx] WebView init error: $e\n$st');
        _bootstrapError ??= 'WebView failed to start: $e';
      } finally {
        if (mounted) {
          setState(() => _webReady = true);
        }
      }
    }());
  }

  void _onBridgeMessage(String text) {
    if (text.startsWith('auth:')) {
      unawaited(() async {
        await PushRegistrationService.setAuthToken(text.substring(5));
        await _reportNativePushStatus();
      }());
    } else if (text == 'push:enable') {
      unawaited(_enableNativePush());
    } else if (text == 'push:status') {
      unawaited(_reportNativePushStatus());
    }
  }

  Future<void> _syncAuthTokenFromWebView() async {
    final webView = _webView;
    if (webView == null) return;
    try {
      await webView.runJavaScript('''
(function(){
  function readToken(){
    try{
      var keys=['posex_test_token','posex_app_token','pos_token'];
      for(var i=0;i<keys.length;i++){
        var v=localStorage.getItem(keys[i]);
        if(v&&String(v).trim()) return String(v).trim();
      }
    }catch(e){}
    return '';
  }
  function send(){
    var t=readToken();
    if(t) PosExNativeBridge.postMessage('auth:'+t);
  }
  send();
  if(!window.__posexAuthHook){
    window.__posexAuthHook=true;
    window.addEventListener('storage', function(e){
      if(!e) return;
      var k=e.key||'';
      if(k.indexOf('token')>=0||k==='posex_test_token'||k==='posex_app_token') send();
    });
  }
})();
''');
    } catch (_) {}
  }

  Future<void> _enableNativePush() async {
    await _syncAuthTokenFromWebView();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await PushRegistrationService.enableFromUser();
    await _reportNativePushStatus();
  }

  Future<void> _reportNativePushStatus() async {
    final webView = _webView;
    if (webView == null) return;
    final status = await PushRegistrationService.getStatus();
    final err = status.error;
    final errJs = err == null
        ? 'null'
        : '"${err.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    try {
      await webView.runJavaScript(
        'window.dispatchEvent(new CustomEvent("posexNativePushStatus",{detail:{enabled:${status.enabled ? 'true' : 'false'},native:true,permissionGranted:${status.permissionGranted ? 'true' : 'false'},registered:${status.registeredWithServer ? 'true' : 'false'},hasFcmToken:${status.hasFcmToken ? 'true' : 'false'},error:$errJs}}));',
      );
    } catch (_) {}
  }

  Future<List<String>> _onShowFileSelector(WebFileSelectorParams params) async {
    final picker = ImagePicker();
    final source =
        params.isCaptureEnabled ? ImageSource.camera : ImageSource.gallery;
    try {
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return <String>[];
      return <String>[Uri.file(image.path).toString()];
    } catch (_) {
      return <String>[];
    }
  }

  void _openPrintPanel() {
    final manager = _printerManager;
    final server = _printServer;
    if (manager == null || server == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrintServerPanel(
          manager: manager,
          server: server,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webView = _webView;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (webView != null && await webView.canGoBack()) {
          await webView.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (webView != null && _webReady && webView.isReady)
                webView.buildWidget()
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFF97316)),
                ),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFF97316)),
                ),
              // Update banner, top.
              if (_update != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: _updateState == UpdateDownloadState.ready
                        ? const Color(0xFF059669)
                        : const Color(0xFFF97316),
                    child: InkWell(
                      onTap: _updateState == UpdateDownloadState.downloading
                          ? null
                          : _runUpdate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _updateState == UpdateDownloadState.ready
                                  ? (Platform.isWindows
                                      ? Icons.restart_alt
                                      : Icons.install_mobile)
                                  : Icons.system_update,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _updateBannerText(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_update!.versionLabel.isNotEmpty)
                                    Text(
                                      _update!.versionLabel,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (_updateError != null &&
                                      _updateError!.isNotEmpty &&
                                      _updateState == UpdateDownloadState.failed)
                                    Text(
                                      _updateError!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_updateState == UpdateDownloadState.downloading)
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  color: Colors.white,
                                ),
                              )
                            else
                              GestureDetector(
                                onTap: () => setState(() => _update = null),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Print-server button — bottom-right, first 5 seconds only.
              if (_showPrintFab)
                Positioned(
                  right: 12,
                  bottom: bottomInset + 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openPrintPanel,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.print, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
