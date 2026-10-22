import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/print_server/print_payload_codec.dart';

void main() {
  test('binaryStringToBytes preserves full 0–255 Latin-1 range', () {
    final chars = String.fromCharCodes(List<int>.generate(256, (i) => i));
    final bytes = binaryStringToBytes(chars);
    expect(bytes.length, 256);
    for (var i = 0; i < 256; i++) {
      expect(bytes[i], i, reason: 'byte $i');
    }
  });

  test('binaryStringToBytes keeps ESC/POS init + high bytes', () {
    // ESC @, then 0xFA (drawer pulse high byte style), GS V 0
    final s = String.fromCharCodes(const [0x1B, 0x40, 0xFA, 0x1D, 0x56, 0x00]);
    expect(binaryStringToBytes(s), [0x1B, 0x40, 0xFA, 0x1D, 0x56, 0x00]);
  });

  test('binaryStringToBytes masks non-Latin-1 instead of throwing', () {
    final s = String.fromCharCodes(const [0x1B, 0x100, 0x41]);
    expect(binaryStringToBytes(s), [0x1B, 0x00, 0x41]);
  });
}
