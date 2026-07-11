import 'dart:async';
import 'dart:io';

import 'package:flutter_thermal_printer/Windows/window_printer_manager.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

/// USB printer access. On Windows uses [WindowPrinterManager] directly so we
/// never touch [FlutterThermalPrinter.instance] (its getter calls
/// flutter_blue_plus, which is Android/iOS only and crashes Windows startup).
class UsbPrinterService {
  FlutterThermalPrinter? _androidFtp;
  WindowPrinterManager? _windowsManager;

  FlutterThermalPrinter get _ftp {
    _androidFtp ??= FlutterThermalPrinter.instance;
    return _androidFtp!;
  }

  WindowPrinterManager get _windows {
    _windowsManager ??= WindowPrinterManager.instance;
    return _windowsManager!;
  }

  /// Scan for currently attached USB printers (best-effort, with timeout).
  Future<List<Printer>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (Platform.isWindows) {
      return _scanWindows(timeout);
    }
    return _scanAndroid(timeout);
  }

  Future<List<Printer>> _scanWindows(Duration timeout) async {
    final completer = Completer<List<Printer>>();
    StreamSubscription<List<Printer>>? sub;
    sub = _windows.devicesStream.listen((printers) {
      final usb = printers
          .where((p) => p.connectionType == ConnectionType.USB)
          .toList();
      if (usb.isNotEmpty && !completer.isCompleted) {
        completer.complete(usb);
      }
    });
    _windows.getPrinters(connectionTypes: const [ConnectionType.USB]);
    final result = await completer.future
        .timeout(timeout, onTimeout: () => <Printer>[]);
    await sub.cancel();
    try {
      await _windows.stopscan();
    } catch (_) {}
    return result;
  }

  Future<List<Printer>> _scanAndroid(Duration timeout) async {
    final completer = Completer<List<Printer>>();
    StreamSubscription<List<Printer>>? sub;
    sub = _ftp.devicesStream.listen((printers) {
      final usb = printers
          .where((p) => p.connectionType == ConnectionType.USB)
          .toList();
      if (usb.isNotEmpty && !completer.isCompleted) {
        completer.complete(usb);
      }
    });
    await _ftp.getPrinters(connectionTypes: const [ConnectionType.USB]);
    final result = await completer.future
        .timeout(timeout, onTimeout: () => <Printer>[]);
    await sub.cancel();
    await _ftp.stopScan();
    return result;
  }

  Printer? _match(List<Printer> devices, String vendorId, String productId) {
    final combined = '$vendorId:$productId';
    for (final p in devices) {
      if (Platform.isWindows) {
        if (p.name == vendorId ||
            p.address == vendorId ||
            p.address == combined ||
            (p.vendorId == vendorId &&
                (productId.isEmpty || p.productId == productId))) {
          return p;
        }
      } else if (p.vendorId == vendorId && p.productId == productId) {
        return p;
      }
    }
    return devices.isNotEmpty ? devices.first : null;
  }

  Future<bool> isPresent(String vendorId, String productId) async {
    final devices = await scan();
    return _match(devices, vendorId, productId) != null;
  }

  Future<bool> send(
    String vendorId,
    String productId,
    List<int> bytes,
  ) async {
    final devices = await scan();
    final printer = _match(devices, vendorId, productId);
    if (printer == null) return false;

    if (Platform.isWindows) {
      await _windows.printData(printer, bytes, longData: true);
      return true;
    }

    try {
      await _ftp.connect(printer);
    } catch (_) {}
    await _ftp.printData(printer, bytes, longData: true);
    return true;
  }
}

/// Pretty identifier persisted in PrinterConfig.address for USB printers.
String usbAddress(Printer p) {
  if (Platform.isWindows) {
    return p.name ?? p.address ?? '';
  }
  return '${p.vendorId ?? ''}:${p.productId ?? ''}';
}
