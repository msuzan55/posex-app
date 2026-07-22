import 'dart:io';

import 'package:flutter/services.dart';

import 'app_diagnostics.dart';

/// Android bridge for saving/sharing files from the WebView (PDF bills, etc.).
///
/// Chrome Custom Tabs / system browsers support Web Share + blob downloads;
/// Android WebView does not — so the page calls these via JS handlers.
class NativeFileBridge {
  NativeFileBridge._();

  static const _channel = MethodChannel('lk.posex.posex_app/file_actions');

  static bool get isSupported => Platform.isAndroid;

  /// Share a file (or text-only if [base64] is empty) via Android ACTION_SEND.
  static Future<Map<String, dynamic>> shareFile({
    required String base64,
    required String fileName,
    String mimeType = 'application/pdf',
    String title = '',
    String text = '',
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

  /// Save a file into the public Downloads folder (MediaStore on Android 10+).
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

  static Map<String, dynamic> _asMap(dynamic result) {
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'ok': true};
  }
}
