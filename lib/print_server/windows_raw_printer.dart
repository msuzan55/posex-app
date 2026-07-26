import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Windows USB/local RAW printing that does not block the UI isolate.
///
/// Replaces `flutter_thermal_printer`'s byte-at-a-time [WritePrinter] loop,
/// which freezes the Flutter UI and stalls localhost `/print` requests.
class WindowsRawPrinter {
  WindowsRawPrinter._();

  static const Duration defaultTimeout = Duration(seconds: 20);

  /// Enumerate local printer names immediately (no 5s periodic scan).
  static List<String> listPrinterNames() {
    if (!Platform.isWindows) return const [];
    try {
      return _listPrinterNamesSync();
    } catch (e) {
      debugPrint('[WindowsRawPrinter] list failed: $e');
      return const [];
    }
  }

  /// Send [bytes] as one RAW spooler job. Runs Win32 work in a background isolate.
  static Future<void> printBytes(
    String printerName,
    List<int> bytes, {
    Duration timeout = defaultTimeout,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsRawPrinter is Windows-only');
    }
    final name = printerName.trim();
    if (name.isEmpty) {
      throw ArgumentError('printerName is empty');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('print payload is empty');
    }

    final payload = Uint8List.fromList(bytes);
    await Isolate.run(() => _printBytesSync(name, payload)).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Windows print timed out after ${timeout.inSeconds}s',
        timeout,
      ),
    );
  }
}

List<String> _listPrinterNamesSync() {
  final names = <String>[];
  final pBuffSize = calloc<DWORD>();
  final bPrinterLen = calloc<DWORD>();
  try {
    EnumPrinters(
      PRINTER_ENUM_LOCAL,
      nullptr,
      2,
      nullptr,
      0,
      pBuffSize,
      bPrinterLen,
    );
    if (pBuffSize.value == 0) return names;

    final rawBuffer = malloc.allocate<BYTE>(pBuffSize.value);
    try {
      final ok = EnumPrinters(
            PRINTER_ENUM_LOCAL,
            nullptr,
            2,
            rawBuffer,
            pBuffSize.value,
            pBuffSize,
            bPrinterLen,
          ) !=
          0;
      if (!ok) return names;
      for (var i = 0; i < bPrinterLen.value; i++) {
        final printer = rawBuffer.cast<PRINTER_INFO_2>() + i;
        final n = printer.ref.pPrinterName.toDartString().trim();
        if (n.isNotEmpty) names.add(n);
      }
      return names;
    } finally {
      free(rawBuffer);
    }
  } finally {
    free(pBuffSize);
    free(bPrinterLen);
  }
}

void _printBytesSync(String printerName, Uint8List bytes) {
  using((Arena alloc) {
    final pPrinterName = printerName.toNativeUtf16(allocator: alloc);
    final phPrinter = alloc<IntPtr>();

    final opened = OpenPrinter(pPrinterName, phPrinter, nullptr);
    if (opened == 0) {
      throw Exception(
        'OpenPrinter failed (${GetLastError()}) for "$printerName"',
      );
    }
    final hPrinter = phPrinter.value;

    try {
      final pDocInfo = alloc<DOC_INFO_1>()
        ..ref.pDocName = 'PosEx'.toNativeUtf16(allocator: alloc)
        ..ref.pDatatype = 'RAW'.toNativeUtf16(allocator: alloc)
        ..ref.pOutputFile = nullptr;

      final jobId = StartDocPrinter(hPrinter, 1, pDocInfo);
      if (jobId == 0) {
        throw Exception('StartDocPrinter failed (${GetLastError()})');
      }

      try {
        if (StartPagePrinter(hPrinter) == 0) {
          throw Exception('StartPagePrinter failed (${GetLastError()})');
        }

        try {
          // One bulk WritePrinter — not one Win32 call per byte.
          final buffer = alloc<Uint8>(bytes.length);
          buffer.asTypedList(bytes.length).setAll(0, bytes);
          final written = alloc<DWORD>();
          final ok = WritePrinter(hPrinter, buffer, bytes.length, written);
          if (ok == 0 || written.value != bytes.length) {
            throw Exception(
              'WritePrinter failed (${GetLastError()}), '
              'wrote ${written.value}/${bytes.length}',
            );
          }
        } finally {
          EndPagePrinter(hPrinter);
        }
      } finally {
        EndDocPrinter(hPrinter);
      }
    } finally {
      ClosePrinter(hPrinter);
    }
  });
}
