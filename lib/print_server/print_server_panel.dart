import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'print_http_server.dart';
import 'print_models.dart';
import 'printer_manager.dart';
import 'usb_printer_service.dart';

const Color _accent = Color(0xFFF97316);
const Color _bg = Color(0xFF0A0A0A);
const Color _card = Color(0xFF151515);

/// Control panel for the embedded print server: shows status, lists/adds/removes
/// printers, sets the default POS / barcode printer and runs a test print.
class PrintServerPanel extends StatefulWidget {
  const PrintServerPanel({
    super.key,
    required this.manager,
    required this.server,
  });

  final PrinterManager manager;
  final PrintHttpServer server;

  @override
  State<PrintServerPanel> createState() => _PrintServerPanelState();
}

class _PrintServerPanelState extends State<PrintServerPanel> {
  PrinterManager get _m => widget.manager;

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _toast(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Minimal ESC/POS test ticket: init + text + feed + cut.
  List<int> _testTicket() {
    final bytes = <int>[];
    bytes.addAll([0x1B, 0x40]); // ESC @ init
    bytes.addAll([0x1B, 0x61, 0x01]); // center
    bytes.addAll('PosEx\n'.codeUnits);
    bytes.addAll('Print server OK\n'.codeUnits);
    bytes.addAll('${DateTime.now()}\n'.codeUnits);
    bytes.addAll([0x0A, 0x0A, 0x0A]); // feed
    bytes.addAll([0x1D, 0x56, 0x00]); // GS V 0 full cut
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Print Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect all',
            onPressed: () async {
              await _m.reconnectAll();
              await _toast('Reconnected printers');
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _m,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Printers',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addNetworkDialog,
                    icon: const Icon(Icons.lan, color: _accent, size: 18),
                    label: const Text('Network',
                        style: TextStyle(color: _accent)),
                  ),
                  TextButton.icon(
                    onPressed: _addBluetoothDialog,
                    icon: const Icon(Icons.bluetooth, color: _accent, size: 18),
                    label: const Text('Bluetooth',
                        style: TextStyle(color: _accent)),
                  ),
                  TextButton.icon(
                    onPressed: _addUsbDialog,
                    icon: const Icon(Icons.usb, color: _accent, size: 18),
                    label: const Text('USB', style: TextStyle(color: _accent)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_m.printers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No printers yet. Add a Network or Bluetooth printer.',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ..._m.printers.map(_printerTile),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard() {
    final running = widget.server.isRunning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: running ? _accent.withValues(alpha: 0.4) : Colors.white24),
      ),
      child: Row(
        children: [
          Icon(running ? Icons.check_circle : Icons.error,
              color: running ? Colors.green : Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(running ? 'Server running' : 'Server stopped',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text('localhost:${PrintHttpServer.port}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _printerTile(PrinterConfig p) {
    final online = _m.isOnline(p.id);
    final isDefaultPos = _m.defaultPosId == p.id;
    final isDefaultBarcode = _m.defaultBarcodeId == p.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(online ? Icons.circle : Icons.circle_outlined,
                  size: 12, color: online ? Colors.green : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              Text(p.transport.label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                onPressed: () => _m.removePrinter(p.id),
              ),
            ],
          ),
          Text(p.address,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Default POS'),
                selected: isDefaultPos,
                onSelected: (_) => _m.setDefaultPos(p.id),
                selectedColor: _accent,
                labelStyle: TextStyle(
                    color: isDefaultPos ? Colors.white : Colors.white70,
                    fontSize: 12),
                backgroundColor: Colors.black26,
              ),
              ChoiceChip(
                label: const Text('Default Barcode'),
                selected: isDefaultBarcode,
                onSelected: (_) => _m.setDefaultBarcode(p.id),
                selectedColor: _accent,
                labelStyle: TextStyle(
                    color: isDefaultBarcode ? Colors.white : Colors.white70,
                    fontSize: 12),
                backgroundColor: Colors.black26,
              ),
              TextButton(
                onPressed: () async {
                  final err = await _m.sendTo(p, _testTicket());
                  await _toast(err == null ? 'Test sent' : 'Failed: $err');
                },
                child: const Text('Test print',
                    style: TextStyle(color: _accent, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addNetworkDialog() async {
    final nameCtrl = TextEditingController(text: 'Network printer');
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');
    bool isBarcode = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Add network printer',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(nameCtrl, 'Name'),
              _field(ipCtrl, 'IP address (e.g. 192.168.1.50)'),
              _field(portCtrl, 'Port', keyboardType: TextInputType.number),
              SwitchListTile(
                value: isBarcode,
                onChanged: (v) => setLocal(() => isBarcode = v),
                title: const Text('Barcode / label printer',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                activeThumbColor: _accent,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add', style: TextStyle(color: _accent))),
          ],
        ),
      ),
    );

    if (ok == true && ipCtrl.text.trim().isNotEmpty) {
      final port = portCtrl.text.trim().isEmpty ? '9100' : portCtrl.text.trim();
      await _m.addPrinter(PrinterConfig(
        id: _newId(),
        name: nameCtrl.text.trim().isEmpty ? 'Network printer' : nameCtrl.text.trim(),
        transport: PrinterTransport.network,
        address: '${ipCtrl.text.trim()}:$port',
        isBarcode: isBarcode,
      ));
    }
  }

  Future<void> _addBluetoothDialog() async {
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      await _toast('Turn on Bluetooth, then try again.');
      return;
    }
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (!mounted) return;
    if (devices.isEmpty) {
      await _toast('No paired Bluetooth printers. Pair it in Android settings first.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Paired Bluetooth printers',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: devices
                .map((d) => ListTile(
                      title: Text(d.name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(d.macAdress,
                          style: const TextStyle(color: Colors.white54)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _m.addPrinter(PrinterConfig(
                          id: _newId(),
                          name: d.name.isEmpty ? 'Bluetooth printer' : d.name,
                          transport: PrinterTransport.bluetooth,
                          address: d.macAdress,
                        ));
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _addUsbDialog() async {
    await _toast('Scanning USB devices…');
    final devices = await UsbPrinterService().scan();
    if (!mounted) return;
    if (devices.isEmpty) {
      await _toast('No USB printer found. Connect via OTG and allow access.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title:
            const Text('USB printers', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: devices
                .map((d) => ListTile(
                      title: Text(d.name ?? 'USB printer',
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(usbAddress(d),
                          style: const TextStyle(color: Colors.white54)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _m.addPrinter(PrinterConfig(
                          id: _newId(),
                          name: (d.name == null || d.name!.isEmpty)
                              ? 'USB printer'
                              : d.name!,
                          transport: PrinterTransport.usb,
                          address: usbAddress(d),
                        ));
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _accent)),
        ),
      ),
    );
  }
}
