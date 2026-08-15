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

  test('parses cumulative receive and send bytes from an AWG dump', () {
    const dump = 'private public 51820 off\n'
        'peer1 (none) 1.2.3.4:4500 0.0.0.0/0 10 1200 340 25\n'
        'peer2 (none) 5.6.7.8:4500 0.0.0.0/0 11 800 60 25\n';

    expect(parseAwgDumpCounters(dump), (received: 2000, sent: 400));
  });

  test('parses Windows adapter byte counters from PowerShell output', () {
    expect(parseWindowsAdapterCounters(' 987654 123456\r\n'), (received: 987654, sent: 123456));
  });
}
