import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

/// PosEx Windows shell — loads the PosEx web app in a WebView.
const String kPosexUrl = 'https://posex.lk/test/';
const String _vcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe';
const String _webView2Url = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703';

WebViewEnvironment? _webViewEnvironment;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;
  try {
    startupError = await _checkRuntimeRequirements();
    startupError ??= await _prepareWebViewEnvironment();
  } catch (e) {
    startupError = 'PosEx failed to start:\n$e';
  }

  runApp(PosexApp(startupError: startupError));
}

Future<String?> _checkRuntimeRequirements() async {
  if (!Platform.isWindows) return null;

  final vcError = _checkVcRedist();
  if (vcError != null) return vcError;

  final webViewVersion = await WebViewEnvironment.getAvailableVersion();
  if (webViewVersion == null) {
    return 'Microsoft Edge WebView2 Runtime is not installed.\n\n'
        'Download and install it from:\n$_webView2Url\n\n'
        'Then restart PosEx.';
  }
  return null;
}

String? _checkVcRedist() {
  final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final sys32 = '$sysRoot${Platform.pathSeparator}System32';
  const required = [
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll',
  ];

  final missing = <String>[];
  for (final dll in required) {
    if (!File('$sys32${Platform.pathSeparator}$dll').existsSync()) {
      missing.add(dll);
    }
  }
  if (missing.isEmpty) return null;

  final installDir = File(Platform.resolvedExecutable).parent;
  final bundledRedist = File(
    '${installDir.path}${Platform.pathSeparator}vc_redist.x64.exe',
  );
  final bundledHint = bundledRedist.existsSync()
      ? '\n\nOr run this file as Administrator:\n${bundledRedist.path}'
      : '';

  return 'Microsoft Visual C++ Runtime is missing (${missing.join(', ')}).\n\n'
      'Install the Visual C++ 2015–2022 Redistributable (x64):\n'
      '$_vcRedistUrl'
      '$bundledHint\n\n'
      'Then restart PosEx.\n\n'
      'Tip: use Launch PosEx.cmd from the unzipped folder.';
}

Future<String?> _prepareWebViewEnvironment() async {
  if (!Platform.isWindows) return null;

  try {
    _webViewEnvironment = await _createWebViewEnvironment(resetProfile: false);
    return null;
  } catch (_) {
    // Corrupt profile is a common silent-crash cause — reset once.
  }

  try {
    _webViewEnvironment = await _createWebViewEnvironment(resetProfile: true);
    return null;
  } catch (e) {
    return 'WebView2 failed to start: $e\n\n'
        'Try: close PosEx, delete this folder, then open again:\n'
        r'%APPDATA%\posex_app\webview2';
  }
}

Future<WebViewEnvironment> _createWebViewEnvironment({
  required bool resetProfile,
}) async {
  final dir = await getApplicationSupportDirectory();
  final userData = Directory('${dir.path}${Platform.pathSeparator}webview2');
  if (resetProfile && userData.existsSync()) {
    await userData.delete(recursive: true);
  }

  return WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(
      userDataFolder: userData.path,
      // GPU issues cause blank/crash windows on some PCs.
      additionalBrowserArguments: '--disable-gpu',
    ),
  );
}

class PosexApp extends StatelessWidget {
  const PosexApp({super.key, this.startupError});

  final String? startupError;

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
      home: startupError != null && startupError!.trim().isNotEmpty
          ? StartupErrorPage(message: startupError!)
          : const PosexWebViewPage(),
    );
  }
}

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFF97316),
                  size: 52,
                ),
                const SizedBox(height: 16),
                const Text(
                  'PosEx could not start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            webViewEnvironment: _webViewEnvironment,
            initialUrlRequest: URLRequest(url: WebUri(kPosexUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
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
