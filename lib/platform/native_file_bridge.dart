import 'dart:io';

import 'package:flutter/services.dart';

import 'app_diagnostics.dart';

/// Android bridge for saving/sharing files and opening WhatsApp from the WebView.
class NativeFileBridge {
  NativeFileBridge._();

  static const _channel = MethodChannel('lk.posex.posex_app/file_actions');

  static bool get isSupported => Platform.isAndroid;

  /// Share a file (or text-only if [base64] is empty) via Android ACTION_SEND.
  ///
  /// Pass [target] as `whatsapp` / `whatsapp_business` to open that app directly.
  static Future<Map<String, dynamic>> shareFile({
    required String base64,
    required String fileName,
    String mimeType = 'application/pdf',
    String title = '',
    String text = '',
    String target = '',
  }) async {
    if (!isSupported) {
      return {'ok': false, 'error': 'Share is only available on Android'};
    }
    try {
      final result = await _channel.invokeMethod<dynamic>('shareFile', {
        'base64': base64,
        'fileName': fileName,
        'mimeType': mimeType,
        'title': title,
        'text': text,
        'target': target,
      });
      return _asMap(result);
    } on PlatformException catch (e, st) {
      await AppDiagnostics.logError('Native share failed', e, st);
      return {'ok': false, 'error': e.message ?? 'Share failed'};
    } catch (e, st) {
      await AppDiagnostics.logError('Native share failed', e, st);
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Save a file into Downloads and show a tap-to-open notification.
  static Future<Map<String, dynamic>> saveFile({
    required String base64,
    required String fileName,
    String mimeType = 'application/pdf',
  }) async {
    if (!isSupported) {
      return {'ok': false, 'error': 'Save is only available on Android'};
    }
    try {
      final result = await _channel.invokeMethod<dynamic>('saveFile', {
        'base64': base64,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return _asMap(result);
    } on PlatformException catch (e, st) {
      await AppDiagnostics.logError('Native save failed', e, st);
      return {'ok': false, 'error': e.message ?? 'Save failed'};
    } catch (e, st) {
      await AppDiagnostics.logError('Native save failed', e, st);
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Open WhatsApp / WhatsApp Business to a chat with optional prefilled text.
  static Future<Map<String, dynamic>> openWhatsApp({
    String phone = '',
    String text = '',
    String variant = 'whatsapp',
  }) async {
    if (!isSupported) {
      return {'ok': false, 'error': 'WhatsApp open is only available on Android'};
    }
    try {
      final result = await _channel.invokeMethod<dynamic>('openWhatsApp', {
        'phone': phone,
        'text': text,
        'variant': variant,
      });
      return _asMap(result);
    } on PlatformException catch (e, st) {
      await AppDiagnostics.logError('Native WhatsApp open failed', e, st);
      return {'ok': false, 'error': e.message ?? 'Could not open WhatsApp'};
    } catch (e, st) {
      await AppDiagnostics.logError('Native WhatsApp open failed', e, st);
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Launch whatsapp:// / intent: / https WhatsApp links outside the WebView.
  static Future<Map<String, dynamic>> openExternalUrl(String url) async {
    if (!isSupported) {
      return {'ok': false, 'error': 'External open is only available on Android'};
    }
    try {
      final result = await _channel.invokeMethod<dynamic>('openExternalUrl', {
        'url': url,
      });
      return _asMap(result);
    } on PlatformException catch (e, st) {
      await AppDiagnostics.logError('Native external open failed', e, st);
      return {'ok': false, 'error': e.message ?? 'Could not open link'};
    } catch (e, st) {
      await AppDiagnostics.logError('Native external open failed', e, st);
      return {'ok': false, 'error': e.toString()};
    }
  }

  static bool shouldOpenExternally(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    if (u.startsWith('whatsapp:')) return true;
    if (u.startsWith('intent:')) return true;
    if (u.contains('api.whatsapp.com')) return true;
    if (u.contains('wa.me/')) return true;
    if (u.contains('web.whatsapp.com')) return true;
    return false;
  }

  static Map<String, dynamic> _asMap(dynamic result) {
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'ok': true};
  }
}
