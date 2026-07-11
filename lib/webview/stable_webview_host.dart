import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/app_diagnostics.dart';
import 'posex_webview_controller.dart';

/// Keeps [InAppWebView] mounted for the lifetime of the screen.
///
/// On Windows, removing or rebuilding the WebView widget destroys the native
/// HWND and can terminate the whole process. This host creates the WebView once
/// and never removes it from the element tree.
class StableWebViewHost extends StatefulWidget {
  const StableWebViewHost({
    super.key,
    required this.controller,
  });

  final PosexWebViewController controller;

  @override
  State<StableWebViewHost> createState() => _StableWebViewHostState();
}

class _StableWebViewHostState extends State<StableWebViewHost>
    with AutomaticKeepAliveClientMixin {
  Widget? _webViewWidget;
  Object? _initError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_mountOnce());
  }

  Future<void> _mountOnce() async {
    try {
      await widget.controller.waitUntilMountable();
      if (!mounted) return;
      final view = widget.controller.buildWidgetOnce();
      if (!mounted) return;
      setState(() => _webViewWidget = view);
      await AppDiagnostics.log('INFO', 'Stable WebView host mounted');
    } catch (e, st) {
      await AppDiagnostics.logError('Stable WebView mount failed', e, st);
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final view = _webViewWidget;
    if (view != null) {
      return SizedBox.expand(child: view);
    }
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'WebView failed to start: $_initError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return const SizedBox.expand(
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      ),
    );
  }
}
