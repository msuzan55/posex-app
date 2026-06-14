import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Cached Android device label for /status (e.g. "Samsung Galaxy A14").
class DeviceInfoService {
  DeviceInfoService._();

  static String? _deviceName;

  static String get cachedDeviceName => _deviceName ?? 'PosEx device';

  static Future<String> deviceName() async {
    if (_deviceName != null) return _deviceName!;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final brand = info.brand.trim();
        final model = info.model.trim();
        if (brand.isNotEmpty && model.isNotEmpty) {
          _deviceName = '$brand $model';
        } else {
          _deviceName = model.isNotEmpty ? model : 'Android device';
        }
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        _deviceName = info.name.trim().isNotEmpty ? info.name : 'iOS device';
      } else {
        _deviceName = 'PosEx device';
      }
    } catch (_) {
      _deviceName = 'PosEx device';
    }
    return _deviceName!;
  }
}
