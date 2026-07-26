import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/platform/posex_environment.dart';

void main() {
  test('PosEx environment URLs', () {
    expect(PosexEnvironment.urlFor(PosexEnvironment.test), 'https://posex.lk/test/');
    expect(PosexEnvironment.urlFor(PosexEnvironment.app), 'https://posex.lk/app/');
  });
}
