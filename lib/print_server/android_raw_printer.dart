import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android USB RAW printing that bypasses [flutter_thermal_printer]'s
/// single-shot [bulkTransfer] (see [AndroidRawUsbPrinter] on the native side).
class AndroidRawPrinter {
  AndroidRawPrinter._();

  static const _channel = MethodChannel('lk.posex.posex_app/usb_raw');

  /// Send [bytes] as chunked USB bulk OUT to the device identified by
  /// [vendorId]:[productId]. Requires USB permission already granted.
  static Future<void> printBytes(
    String vendorId,
    String productId,
    List<int> bytes,
  ) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('AndroidRawPrinter is Android-only');
    }
    final vendor = vendorId.trim();
    if (vendor.isEmpty) {
      throw ArgumentError('vendorId is empty');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('print payload is empty');
    }

    final payload =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      await _channel.invokeMethod<bool>('printBytes', {
        'vendorId': vendor,
        'productId': productId.trim(),
        'data': payload,
      });
    } on PlatformException catch (e) {
      debugPrint('[AndroidRawPrinter] print failed: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
