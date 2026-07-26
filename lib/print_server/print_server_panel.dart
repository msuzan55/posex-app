import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../platform/platform_features.dart';
import '../platform/posex_environment.dart';
import 'print_http_server.dart';
import 'print_models.dart';
import 'printer_manager.dart';
import 'usb_printer_service.dart';

const Color _accent = Color(0xFFF97316);
const Color _bg = Color(0xFF0A0A0A);
const Color _card = Color(0xFF151515);

/// Settings + print server: PosEx site, status, printers, defaults, test print.
class PrintServerPanel extends StatefulWidget {
  const PrintServerPanel({
    super.key,
    this.manager,
    this.server,
    required this.currentEnvironment,
    required this.onEnvironmentSelected,
  });

  final PrinterManager? manager;
  final PrintHttpServer? server;
  final String currentEnvironment;
  final Future<void> Function(String environment) onEnvironmentSelected;

  @override
  State<PrintServerPanel> createState() => _PrintServerPanelState();
}

class _PrintServerPanelState extends State<PrintServerPanel> {
  PrinterManager? get _m => widget.manager;

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

  Future<void> _confirmSwitchEnvironment(String env) async {
    if (env == widget.currentEnvironment) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Switch PosEx site?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Switch to ${PosexEnvironment.labelFor(env)}?\n\n'
          'This clears saved login and offline web data, then loads the selected site. '
          'Printer settings are kept.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & switch',
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.onEnvironmentSelected(env);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        actions: [
          if (_m != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect all',
              onPressed: () async {
                await _m!.reconnectAll();
                await _toast('Reconnected printers');
              },
            ),
        ],
      ),
      body: _m == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _environmentCard(),
                const SizedBox(height: 16),
                const Text(
                  'Print server is still starting…',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            )
          : ListenableBuilder(
              listenable: _m!,
              builder: (context, _) {
                final manager = _m!;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _environmentCard(),
                    const SizedBox(height: 16),
                    _statusCard(),
                    const SizedBox(height: 16),
                    const Text('Printers',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.start,
                      children: [
                        _addPrinterChip(
                          icon: Icons.lan,
                          label: 'Network',
                          onPressed: _addNetworkDialog,
                        ),
                        if (bluetoothPrinterSupported)
                          _addPrinterChip(
                            icon: Icons.bluetooth,
                            label: 'Bluetooth',
                            onPressed: _addBluetoothDialog,
                          ),
                        if (usbPrinterSupported)
                          _addPrinterChip(
                            icon: Icons.usb,
                            label: 'USB',
                            onPressed: _addUsbDialog,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (manager.printers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No printers yet. $printPanelPlatformHint',
                            style: const TextStyle(color: Colors.white54)),
                      )
                    else
                      ...manager.printers.map(_printerTile),
                  ],
                );
              },
            ),
    );
  }

  Widget _environmentCard() {
    final current = widget.currentEnvironment;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PosEx site',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Changing site clears login / offline web data and reloads.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _envOption(
            value: PosexEnvironment.test,
            selected: current == PosexEnvironment.test,
            title: 'posex.lk/test',
            subtitle: 'Staging',
          ),
          _envOption(
            value: PosexEnvironment.app,
            selected: current == PosexEnvironment.app,
            title: 'posex.lk/app',
            subtitle: 'Production',
          ),
        ],
      ),
    );
  }

  Widget _envOption({
    required String value,
    required bool selected,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: selected ? null : () => unawaited(_confirmSwitchEnvironment(value)),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _accent.withValues(alpha: 0.18) : Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _accent : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _accent : Colors.white38,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        )),
                    Text(subtitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    final running = widget.server?.isRunning ?? false;
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
    final manager = _m!;
    final online = manager.isOnline(p.id);
    final isDefaultPos = manager.defaultPosId == p.id;
    final isDefaultBarcode = manager.defaultBarcodeId == p.id;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(online ? Icons.circle : Icons.circle_outlined,
                    size: 12, color: online ? Colors.green : Colors.white38),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${p.transport.label} · ${p.address}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                onPressed: () => manager.removePrinter(p.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Default POS'),
                selected: isDefaultPos,
                onSelected: (_) => manager.setDefaultPos(p.id),
                selectedColor: _accent,
                labelStyle: TextStyle(
                    color: isDefaultPos ? Colors.white : Colors.white70,
                    fontSize: 12),
                backgroundColor: Colors.black26,
              ),
              ChoiceChip(
                label: const Text('Default Barcode'),
                selected: isDefaultBarcode,
                onSelected: (_) => manager.setDefaultBarcode(p.id),
                selectedColor: _accent,
                labelStyle: TextStyle(
                    color: isDefaultBarcode ? Colors.white : Colors.white70,
                    fontSize: 12),
                backgroundColor: Colors.black26,
              ),
              TextButton(
                onPressed: () async {
                  final err = await manager.sendTo(p, _testTicket());
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
      await _m!.addPrinter(PrinterConfig(
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
                        await _m!.addPrinter(PrinterConfig(
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
      await _toast(
        Platform.isWindows
            ? 'No USB printer found. Connect the printer and try again.'
            : 'No USB printer found. Connect via OTG and allow access.',
      );
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
                        await _m!.addPrinter(PrinterConfig(
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

  Widget _addPrinterChip({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _accent,
        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
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
