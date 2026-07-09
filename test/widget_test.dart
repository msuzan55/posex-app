import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/main.dart';

void main() {
  test('PosEx URL points at staging web app', () {
    expect(kPosexUrl, 'https://posex.lk/test/');
  });
}
