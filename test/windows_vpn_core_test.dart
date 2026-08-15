import 'package:flutter_test/flutter_test.dart';
import 'package:pokolenie_vpn/core/windows_vpn_core.dart';

void main() {
  test('keeps a Cyrillic Windows config path as one argument', () {
    final line = buildWindowsArgumentLine(<String>[
      '/installtunnelservice',
      r'C:\Users\Тест\Рабочий стол\Pokolenie WARP\runtime\pokolenie-warp.conf',
    ]);

    expect(
      line,
      r'"/installtunnelservice" "C:\Users\Тест\Рабочий стол\Pokolenie WARP\runtime\pokolenie-warp.conf"',
    );
  });

  test('escapes quotes and trailing backslashes for Windows argv', () {
    expect(buildWindowsArgumentLine(<String>[r'a"b', r'C:\folder\']), r'"a\"b" "C:\folder\\"');
  });
}
