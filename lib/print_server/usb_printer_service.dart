import 'dart:async';
import 'dart:io';

import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import 'windows_raw_printer.dart';

/// USB printer access.
///
/// Android uses [FlutterThermalPrinter]. Windows uses [WindowsRawPrinter]
/// (bulk WritePrinter off the UI isolate) and never touches
/// [FlutterThermalPrinter.instance] (its getter pulls in flutter_blue_plus).
class UsbPrinterService {
  FlutterThermalPrinter? _androidFtp;

  FlutterThermalPrinter get _ftp {
    _androidFtp ??= FlutterThermalPrinter.instance;
    return _androidFtp!;
  }

  /// Scan for currently attached USB printers (best-effort, with timeout).
  Future<List<Printer>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (Platform.isWindows) {
      return _scanWindows();
    }
    return _scanAndroid(timeout);
  }

  List<Printer> _scanWindows() {
    return WindowsRawPrinter.listPrinterNames()
        .map(
          (name) => Printer(
            vendorId: name,
            productId: 'N/A',
            name: name,
            connectionType: ConnectionType.USB,
            address: name,
            isConnected: true,
          ),
        )
        .toList(growable: false);
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
                (productId.isEmpty ||
                    productId == 'N/A' ||
                    p.productId == productId))) {
          return p;
        }
      } else if (p.vendorId == vendorId && p.productId == productId) {
        return p;
      }
    }
    // Windows stores the spooler name in address; prefer exact name open.
    if (Platform.isWindows && vendorId.isNotEmpty) {
      return Printer(
        vendorId: vendorId,
        productId: productId.isEmpty ? 'N/A' : productId,
        name: vendorId,
        connectionType: ConnectionType.USB,
        address: vendorId,
        isConnected: true,
      );
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
    if (Platform.isWindows) {
      final devices = _scanWindows();
      final printer = _match(devices, vendorId, productId);
      if (printer == null) return false;
      final name = (printer.name ?? printer.address ?? vendorId).trim();
      if (name.isEmpty) return false;
      await WindowsRawPrinter.printBytes(name, bytes);
      return true;
    }

    final devices = await scan();
    final printer = _match(devices, vendorId, productId);
    if (printer == null) return false;

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
