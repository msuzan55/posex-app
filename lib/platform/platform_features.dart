import 'dart:io';

/// Whether native FCM push registration is supported on this platform.
bool get nativePushSupported => Platform.isAndroid;

/// Whether Bluetooth thermal printers can be used on this platform.
bool get bluetoothPrinterSupported => Platform.isAndroid;

/// Whether USB thermal printers can be scanned on this platform.
bool get usbPrinterSupported => Platform.isAndroid || Platform.isWindows;

/// Human-readable platform label for empty-state copy in the print panel.
String get printPanelPlatformHint {
  if (Platform.isAndroid) {
    return 'Add a Network, Bluetooth, or USB printer.';
  }
  if (Platform.isWindows) {
    return 'Add a Network or USB printer.';
  }
  return 'Add a Network printer.';
}
