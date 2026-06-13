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

  bool _loading = true;
  bool _fabProminent = true; // brighter for the first 5s
  Timer? _fabTimer;

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
