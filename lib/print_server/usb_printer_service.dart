import 'dart:async';

import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

/// Thin wrapper over flutter_thermal_printer for USB (printer-class) devices.
/// USB printers are identified by "vendorId:productId".
class UsbPrinterService {
  final FlutterThermalPrinter _ftp = FlutterThermalPrinter.instance;

  /// Scan for currently attached USB printers (best-effort, with timeout).
  Future<List<Printer>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
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
    for (final p in devices) {
      if (p.vendorId == vendorId && p.productId == productId) return p;
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
    // connect() triggers the USB permission request on first use; with the
    // "use by default" grant (manifest attach filter) permission is already
    // held, so don't gate printing on its return value.
    try {
      await _ftp.connect(printer);
    } catch (_) {}
    await _ftp.printData(printer, bytes, longData: true);
    return true;
  }
}

/// Pretty identifier persisted in PrinterConfig.address for USB printers.
String usbAddress(Printer p) => '${p.vendorId ?? ''}:${p.productId ?? ''}';
