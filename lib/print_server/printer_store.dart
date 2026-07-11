import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'print_models.dart';

/// Persists the printer list + which printer is the default POS / barcode.
class PrinterStore {
  static const _kPrinters = 'posex_print_printers';
  static const _kDefaultPos = 'posex_print_default_pos';
  static const _kDefaultBarcode = 'posex_print_default_barcode';

  Future<List<PrinterConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrinters);
    if (raw == null || raw.isEmpty) return <PrinterConfig>[];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => PrinterConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return <PrinterConfig>[];
    }
  }

  Future<void> save(List<PrinterConfig> printers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrinters,
      jsonEncode(printers.map((p) => p.toJson()).toList()),
    );
  }

  Future<String?> get defaultPosId async =>
      (await SharedPreferences.getInstance()).getString(_kDefaultPos);

  Future<String?> get defaultBarcodeId async =>
      (await SharedPreferences.getInstance()).getString(_kDefaultBarcode);

  Future<void> setDefaultPos(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kDefaultPos);
    } else {
      await prefs.setString(_kDefaultPos, id);
    }
  }

  Future<void> setDefaultBarcode(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kDefaultBarcode);
    } else {
      await prefs.setString(_kDefaultBarcode, id);
    }
  }
}
