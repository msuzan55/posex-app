import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/main.dart';

void main() {
  test('PosEx app targets the staging web app URL', () {
    expect(kPosexUrl, 'https://posex.lk/test/');
  });
}
