import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'print_server/device_info_service.dart';
import 'print_server/print_foreground_service.dart';
import 'print_server/print_http_server.dart';
import 'print_server/print_server_panel.dart';
import 'print_server/printer_manager.dart';
import 'print_server/printer_store.dart';
import 'push/push_registration_service.dart';
import 'update/update_service.dart';

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
  WebViewController? _controller;
  PrinterManager? _printerManager;
  PrintHttpServer? _printServer;
  final UpdateService _updateService = UpdateService();

  bool _loading = true;
  bool _webReady = false;
  bool _showPrintFab = true;
  String? _bootstrapError;
  Timer? _fabTimer;
  Timer? _probeTimer;
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
    // Keep print server + foreground service running for remote printing.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-assert foreground service when app goes to background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      PrintForegroundService.start();
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _requestPermissions();

      final manager = PrinterManager(PrinterStore());
      final server = PrintHttpServer(manager);
      _printerManager = manager;
      _printServer = server;

      await DeviceInfoService.deviceName();

      unawaited(PushRegistrationService.init());

      final printStarted = await server.start();
      if (!printStarted) {
        _bootstrapError = 'Print server could not start on port ${PrintHttpServer.port}';
      }

      await manager.init();

      // Notification permission before foreground service (Android 13+).
      final notif = await Permission.notification.status;
      if (notif.isGranted) {
        await PrintForegroundService.start();
      }

      _probeTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        manager.reconnectAll();
      });
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
        await _updateService.installDownloadedApk();
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
        return 'Update ready — tap to install now';
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
    await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
      Permission.notification,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'PosExNativeBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final text = message.message;
          if (text.startsWith('auth:')) {
            PushRegistrationService.setAuthToken(text.substring(5));
            _reportNativePushStatus();
          } else if (text == 'push:enable') {
            _enableNativePush();
          } else if (text == 'push:status') {
            _reportNativePushStatus();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _syncAuthTokenFromWebView();
            _reportNativePushStatus();
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] ${error.errorCode} ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(kPosexUrl));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setMixedContentMode(MixedContentMode.alwaysAllow);
      platform.setOnShowFileSelector(_onShowFileSelector);
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }

    _controller = controller;
    _webReady = true;
    if (mounted) setState(() {});
  }

  Future<void> _syncAuthTokenFromWebView() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
(function(){
  function send(){
    try{
      var t=localStorage.getItem('pos_token');
      if(t) PosExNativeBridge.postMessage('auth:'+t);
    }catch(e){}
  }
  send();
  if(!window.__posexAuthHook){
    window.__posexAuthHook=true;
    window.addEventListener('storage', function(e){
      if(!e||e.key==='pos_token') send();
    });
  }
})();
''');
    } catch (_) {}
  }

  Future<void> _enableNativePush() async {
    final enabled = await PushRegistrationService.enableFromUser();
    await _reportNativePushStatus(enabled: enabled);
  }

  Future<void> _reportNativePushStatus({bool? enabled}) async {
    final controller = _controller;
    if (controller == null) return;
    final ok = enabled ?? await PushRegistrationService.queryStatus();
    try {
      await controller.runJavaScript(
        'window.dispatchEvent(new CustomEvent("posexNativePushStatus",{detail:{enabled:${ok ? 'true' : 'false'},native:true}}));',
      );
    } catch (_) {}
  }

  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
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
    final controller = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (controller != null && await controller.canGoBack()) {
          controller.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (controller != null && _webReady)
                WebViewWidget(controller: controller)
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
                                  ? Icons.install_mobile
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
                  bottom: 12,
                  child: GestureDetector(
                    onTap: _openPrintPanel,
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
            ],
          ),
        ),
      ),
    );
  }
}
