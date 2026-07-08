import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/update/windows_install_paths.dart';

void main() {
  group('WindowsInstallPaths helpers', () {
    test('unsafeLocationUserMessage explains archive extraction', () {
      final message = WindowsInstallPaths.unsafeLocationUserMessage(
        'flutter_windows.dll is missing.',
      );
      expect(message, contains('ZIP/RAR'));
      expect(message, contains('PosEx-Setup.exe'));
    });

    test('WindowsLaunchCheck ready state can continue', () {
      expect(WindowsLaunchCheck.ready.canContinue, isTrue);
      expect(WindowsLaunchCheck.ready.relaunching, isFalse);
    });

    test('WindowsLaunchCheck blocked state cannot continue', () {
      final blocked = WindowsLaunchCheck.blocked('test');
      expect(blocked.canContinue, isFalse);
      expect(blocked.blockMessage, 'test');
    });
  });
}
