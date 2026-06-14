import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'print_server/print_http_server.dart';
import 'print_server/print_server_panel.dart';
import 'print_server/printer_manager.dart';
import 'print_server/printer_store.dart';
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

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late final PrinterManager _printerManager;
  late final PrintHttpServer _printServer;
  final UpdateService _updateService = UpdateService();

  bool _loading = true;
  bool _fabProminent = true; // brighter for the first 5s
  Timer? _fabTimer;
  UpdateInfo? _update;
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _printerManager = PrinterManager(PrinterStore());
    _printServer = PrintHttpServer(_printerManager);
    _bootstrap();
    _initWebView();

    // Floating button is prominent for 5s, then dims but stays tappable.
    _fabTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _fabProminent = false);
    });
  }

  @override
  void dispose() {
    _fabTimer?.cancel();
    _printServer.stop();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _requestPermissions();
    await _printServer.start(); // auto-start on launch
    await _printerManager.init(); // load + auto-reconnect saved printers
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await _updateService.checkForUpdate();
    if (mounted && info != null) setState(() => _update = info);
  }

  Future<void> _runUpdate() async {
    final info = _update;
    if (info == null || _downloadProgress != null) return;
    setState(() => _downloadProgress = 0);
    try {
      await _updateService.downloadAndInstall(
        info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
    } catch (_) {
      // ignored — banner stays so the user can retry
    }
    if (mounted) setState(() => _downloadProgress = null);
  }

  /// Camera + photo/storage so product-photo capture and gallery upload work.
  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(kPosexUrl));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      // Reach the embedded http://localhost:9753 server from the HTTPS page.
      platform.setMixedContentMode(MixedContentMode.alwaysAllow);
      platform.setOnShowFileSelector(_onShowFileSelector);
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }

    _controller = controller;
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrintServerPanel(
          manager: _printerManager,
          server: _printServer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
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
                    color: const Color(0xFFF97316),
                    child: InkWell(
                      onTap: _downloadProgress == null ? _runUpdate : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _downloadProgress == null
                                    ? 'Update available — tap to install'
                                    : 'Downloading update… ${(_downloadProgress! * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (_downloadProgress == null)
                              GestureDetector(
                                onTap: () => setState(() => _update = null),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 20),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Print-server button, bottom-right.
              Positioned(
                right: 12,
                bottom: 12,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 500),
                  opacity: _fabProminent ? 1.0 : 0.35,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
