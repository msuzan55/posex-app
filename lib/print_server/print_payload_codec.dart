import 'dart:convert';

/// Decode the PosEx web app's localhost `/print` `content` field.
///
/// The web client builds ESC/POS as a Uint8Array, then
/// `thermalToLatin1String` → `String.fromCharCode(byte)` for each byte, then
/// JSON-POSTs that string. Round-trip must preserve every value 0–255.
List<int> binaryStringToBytes(String s) {
  if (s.isEmpty) return const <int>[];
  try {
    return latin1.encode(s);
  } on ArgumentError {
    // Defensive: mask code units if a non-Latin-1 char slipped through.
    return s.codeUnits.map((c) => c & 0xFF).toList(growable: false);
  }
}
