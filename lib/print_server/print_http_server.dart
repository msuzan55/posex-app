import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'printer_manager.dart';

/// Embedded HTTP print server on :9753, mirroring the contract the PosEx web
/// app's localhostPrintService expects:
///   GET  /status -> { status, device_name, pos_printer, barcode_printer,
///                     pos_printer_name, barcode_printer_name }
///   POST /print  -> { type:"pos"|"barcode", content } | { type:"cash_drawer", command(base64) }
class PrintHttpServer {
  PrintHttpServer(this._manager);

  static const int port = 9753;

  final PrinterManager _manager;
  final List<HttpServer> _servers = <HttpServer>[];

  bool get isRunning => _servers.isNotEmpty;

  static const Map<String, String> _cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  Future<bool> start() async {
    if (_servers.isNotEmpty) return true;

    // WebView may resolve localhost to either 127.0.0.1 or ::1 depending on
    // platform/runtime. Bind both loopback families so localhost is reliable.
    await _bind(InternetAddress.loopbackIPv4);
    await _bind(InternetAddress.loopbackIPv6);

    if (_servers.isEmpty) {
      debugPrint('[PrintServer] start failed: could not bind on $port');
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    for (final server in _servers) {
      await server.close(force: true);
    }
    _servers.clear();
  }

  Future<void> _bind(InternetAddress address) async {
    try {
      final server = await shelf_io.serve(
        _handler,
        address,
        port,
        shared: true,
      );
      _servers.add(server);
    } catch (e) {
      // One family may already be covered by another bind; keep going.
      debugPrint('[PrintServer] bind ${address.address} failed: $e');
    }
  }

  Future<Response> _handler(Request request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: _cors);
    }

    final path = '/${request.url.path}';
    if (request.method == 'GET' && path == '/status') {
      return _json(_manager.statusJson());
    }
    if (request.method == 'POST' && path == '/print') {
      return _handlePrint(request);
    }
    return Response.notFound(
      jsonEncode({'ok': false, 'message': 'Not found'}),
      headers: {..._cors, 'content-type': 'application/json'},
    );
  }

  Future<Response> _handlePrint(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final type = (data['type'] ?? 'pos') as String;

      late final List<int> bytes;
      bool barcode = false;

      switch (type) {
        case 'barcode':
          barcode = true;
          bytes = _stringToBytes((data['content'] ?? '') as String);
          break;
        case 'cash_drawer':
          bytes = base64Decode((data['command'] ?? '') as String);
          break;
        case 'pos':
        default:
          bytes = _stringToBytes((data['content'] ?? '') as String);
          break;
      }

      if (bytes.isEmpty) {
        return _json({'ok': false, 'message': 'Empty print payload'},
            status: 400);
      }

      final error = await _manager.sendToRole(barcode: barcode, bytes: bytes);
      if (error == null) {
        return _json({'ok': true, 'status': 'success'});
      }
      return _json({'ok': false, 'status': 'error', 'message': error},
          status: 502);
    } catch (e) {
      return _json({'ok': false, 'message': e.toString()}, status: 500);
    }
  }

  /// The web app sends ESC/POS / ZPL as a raw string where each char code is a
  /// byte (0-255). Map code units to bytes.
  List<int> _stringToBytes(String s) =>
      s.codeUnits.map((c) => c & 0xFF).toList(growable: false);

  Response _json(Map<String, dynamic> data, {int status = 200}) => Response(
        status,
        body: jsonEncode(data),
        headers: {..._cors, 'content-type': 'application/json'},
      );
}
