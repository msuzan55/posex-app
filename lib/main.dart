import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// PosEx standalone app — a WebView wrapper around the PosEx web app with
/// native camera / gallery upload and localhost (LAN) printer support.
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initWebView();
  }

  /// Request camera + photo/storage up front so product-photo capture and
  /// gallery upload work without surprises mid-flow.
  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
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

    // Android-specific: localhost (HTTP) printing, gallery upload, camera.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      // Let the HTTPS page reach the http://<host>:9753 local print server.
      platform.setMixedContentMode(MixedContentMode.alwaysAllow);
      // <input type="file"> → native gallery / camera picker.
      platform.setOnShowFileSelector(_onShowFileSelector);
      // getUserMedia() (in-page product camera) permission prompt.
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }

    _controller = controller;
  }

  /// Handle web `<input type="file">`. Uses the camera when the input asks to
  /// capture, otherwise the gallery. Returns file URIs for the WebView.
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
            ],
          ),
        ),
      ),
    );
  }
}
