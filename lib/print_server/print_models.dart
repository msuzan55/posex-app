/// How a printer is physically reached.
enum PrinterTransport { network, bluetooth, usb }

extension PrinterTransportLabel on PrinterTransport {
  String get label {
    switch (this) {
      case PrinterTransport.network:
        return 'Network';
      case PrinterTransport.bluetooth:
        return 'Bluetooth';
      case PrinterTransport.usb:
        return 'USB';
    }
  }
}

/// A saved printer. `address` meaning depends on transport:
///  - network:   "192.168.1.50:9100"
///  - bluetooth: MAC address
///  - usb:       device identifier
class PrinterConfig {
  PrinterConfig({
    required this.id,
    required this.name,
    required this.transport,
    required this.address,
    this.isBarcode = false,
  });

  final String id;
  final String name;
  final PrinterTransport transport;
  final String address;

  /// true  → barcode/label printer (receives ZPL),
  /// false → POS receipt printer (receives ESC/POS).
  final bool isBarcode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        'address': address,
        'isBarcode': isBarcode,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        transport: PrinterTransport.values.firstWhere(
          (t) => t.name == json['transport'],
          orElse: () => PrinterTransport.network,
        ),
        address: (json['address'] ?? '') as String,
        isBarcode: json['isBarcode'] == true,
      );
}
