import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

/// PosEx Windows shell — loads the PosEx web app in a WebView.
const String kPosexUrl = 'https://posex.lk/test/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: Colors.black,
    title: 'PosEx',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const PosexApp());
}

class PosexApp extends StatelessWidget {
  const PosexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PosEx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF97316),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PosexWebViewPage(),
    );
  }
}

class PosexWebViewPage extends StatefulWidget {
  const PosexWebViewPage({super.key});

  @override
  State<PosexWebViewPage> createState() => _PosexWebViewPageState();
}

class _PosexWebViewPageState extends State<PosexWebViewPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _error;
  double _progress = 0;

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _loading = true;
      _progress = 0;
    });
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(kPosexUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(kPosexUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useHybridComposition: true,
              isInspectable: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = true;
                _error = null;
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _progress = 1;
              });
            },
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame != true) return;
              if (!mounted) return;
              setState(() {
                _loading = false;
                _error =
                    'Could not load PosEx.\n${error.description}\n\nCheck your internet connection and try again.';
              });
            },
            onReceivedHttpError: (controller, request, response) {
              if (request.isForMainFrame != true) return;
              final code = response.statusCode ?? 0;
              if (code < 400) return;
              if (!mounted) return;
              setState(() {
                _loading = false;
                _error =
                    'PosEx returned HTTP $code.\nCheck https://posex.lk and try again.';
              });
            },
          ),
          if (_loading)
            ColoredBox(
              color: const Color(0xCC000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFF97316)),
                    const SizedBox(height: 16),
                    Text(
                      'Loading PosEx…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 180,
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        color: const Color(0xFFF97316),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            ColoredBox(
              color: const Color(0xF00A0A0A),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Color(0xFFF97316),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'PosEx could not load',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF97316),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
