import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'device_info_service.dart';
import 'print_models.dart';
import 'printer_store.dart';
import 'usb_printer_service.dart';

/// Owns the printer list, (auto) connections and the actual byte sending for
/// all transports. Notifies listeners so the control panel can live-update.
class PrinterManager extends ChangeNotifier {
  PrinterManager(this._store);

  final PrinterStore _store;

  List<PrinterConfig> _printers = <PrinterConfig>[];
  String? _defaultPosId;
  String? _defaultBarcodeId;

  /// Best-effort reachability cache, keyed by printer id.
  final Map<String, bool> _online = <String, bool>{};

  /// MAC of the currently connected Bluetooth printer (plugin allows one).
  String? _btConnectedMac;

  final UsbPrinterService _usb = UsbPrinterService();

  List<PrinterConfig> get printers => List.unmodifiable(_printers);
  String? get defaultPosId => _defaultPosId;
  String? get defaultBarcodeId => _defaultBarcodeId;

  bool isOnline(String id) => _online[id] == true;

  /// Printers that passed the last reachability probe.
  int get connectedPrinterCount =>
      _online.values.where((online) => online).length;

  bool get hasConnectedPrinter => connectedPrinterCount > 0;

  PrinterConfig? _byId(String? id) {
    if (id == null) return null;
    for (final p in _printers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Load saved printers + defaults, then try to connect to all of them.
  Future<void> init() async {
    _printers = await _store.load();
    _defaultPosId = await _store.defaultPosId;
    _defaultBarcodeId = await _store.defaultBarcodeId;
    notifyListeners();
    await reconnectAll();
  }

  Future<void> reconnectAll() async {
    var changed = false;
    for (final p in _printers) {
      final before = _online[p.id];
      final now = await _probe(p);
      _online[p.id] = now;
      if (before != now) changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> addPrinter(PrinterConfig printer) async {
    _printers = [..._printers, printer];
    await _store.save(_printers);
    // First POS/barcode printer becomes the default for its role.
    if (printer.isBarcode) {
      _defaultBarcodeId ??= printer.id;
      await _store.setDefaultBarcode(_defaultBarcodeId);
    } else {
      _defaultPosId ??= printer.id;
      await _store.setDefaultPos(_defaultPosId);
    }
    _online[printer.id] = await _probe(printer);
    notifyListeners();
  }

  Future<void> removePrinter(String id) async {
    _printers = _printers.where((p) => p.id != id).toList();
    await _store.save(_printers);
    if (_defaultPosId == id) {
      _defaultPosId = null;
      await _store.setDefaultPos(null);
    }
    if (_defaultBarcodeId == id) {
      _defaultBarcodeId = null;
      await _store.setDefaultBarcode(null);
    }
    _online.remove(id);
    notifyListeners();
  }

  Future<void> setDefaultPos(String id) async {
    _defaultPosId = id;
    await _store.setDefaultPos(id);
    notifyListeners();
  }

  Future<void> setDefaultBarcode(String id) async {
    _defaultBarcodeId = id;
    await _store.setDefaultBarcode(id);
    notifyListeners();
  }

  /// Status payload the web app's localhostPrintService expects.
  Map<String, dynamic> statusJson() {
    final pos = _byId(_defaultPosId);
    final barcode = _byId(_defaultBarcodeId);
    final posOnline =
        _defaultPosId != null && _defaultPosId!.isNotEmpty && isOnline(_defaultPosId!);
    final barcodeOnline = _defaultBarcodeId != null &&
        _defaultBarcodeId!.isNotEmpty &&
        isOnline(_defaultBarcodeId!);
    return {
      'status': 'online',
      'device_name': DeviceInfoService.cachedDeviceName,
      'pos_printer': posOnline,
      'barcode_printer': barcodeOnline,
      'pos_printer_name': posOnline ? pos?.name : null,
      'barcode_printer_name': barcodeOnline ? barcode?.name : null,
    };
  }

  /// Send raw bytes to the default printer for the given role.
  /// Returns null on success, or an error message.
  Future<String?> sendToRole({required bool barcode, required List<int> bytes}) async {
    final printer = _byId(barcode ? _defaultBarcodeId : _defaultPosId) ??
        // Fall back to POS printer for cash-drawer / when no barcode set.
        _byId(_defaultPosId);
    if (printer == null) {
      return 'No ${barcode ? 'barcode' : 'POS'} printer selected in the app.';
    }
    return sendTo(printer, bytes);
  }

  Future<String?> sendTo(PrinterConfig printer, List<int> bytes) async {
    try {
      switch (printer.transport) {
        case PrinterTransport.network:
          await _sendNetwork(printer.address, bytes);
          break;
        case PrinterTransport.bluetooth:
          if (!Platform.isAndroid) {
            return 'Bluetooth printers are supported on Android only.';
          }
          final ok = await _sendBluetooth(printer.address, bytes);
          if (!ok) return 'Bluetooth printer not reachable.';
          break;
        case PrinterTransport.usb:
          final vp = _vendorProduct(printer.address);
          final ok = await _usb.send(vp.vendor, vp.product, bytes);
          if (!ok) return 'USB printer not reachable.';
          break;
      }
      _online[printer.id] = true;
      notifyListeners();
      return null;
    } catch (e) {
      _online[printer.id] = false;
      notifyListeners();
      return e.toString();
    }
  }

  // ---- transports ---------------------------------------------------------

  ({String host, int port}) _hostPort(String address) {
    final parts = address.split(':');
    final host = parts.isNotEmpty ? parts[0] : '127.0.0.1';
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
    return (host: host, port: port);
  }

  Future<void> _sendNetwork(String address, List<int> bytes) async {
    final hp = _hostPort(address);
    final socket = await Socket.connect(
      hp.host,
      hp.port,
      timeout: const Duration(seconds: 6),
    );
    socket.add(bytes);
    await socket.flush();
    await socket.close();
    socket.destroy();
  }

  Future<bool> _sendBluetooth(String mac, List<int> bytes) async {
    if (!await _ensureBluetooth(mac)) return false;
    return PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<bool> _ensureBluetooth(String mac) async {
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected && _btConnectedMac == mac) return true;
    if (connected && _btConnectedMac != mac) {
      await PrintBluetoothThermal.disconnect;
      _btConnectedMac = null;
    }
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (ok) _btConnectedMac = mac;
    return ok;
  }

  /// Lightweight reachability check used for status/auto-reconnect.
  Future<bool> _probe(PrinterConfig printer) async {
    try {
      switch (printer.transport) {
        case PrinterTransport.network:
          final hp = _hostPort(printer.address);
          final s = await Socket.connect(hp.host, hp.port,
              timeout: const Duration(seconds: 3));
          s.destroy();
          return true;
        case PrinterTransport.bluetooth:
          if (!Platform.isAndroid) return false;
          return _ensureBluetooth(printer.address);
        case PrinterTransport.usb:
          if (Platform.isWindows) {
            // USB scan uses native printer APIs — run only when sending, not at startup.
            return false;
          }
          final vp = _vendorProduct(printer.address);
          return _usb.isPresent(vp.vendor, vp.product);
      }
    } catch (_) {
      return false;
    }
  }

  ({String vendor, String product}) _vendorProduct(String address) {
    final parts = address.split(':');
    return (
      vendor: parts.isNotEmpty ? parts[0] : '',
      product: parts.length > 1 ? parts[1] : '',
    );
  }
}
