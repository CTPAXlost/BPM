import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokolenie_vpn/models/vpn_protocol.dart';
import 'package:pokolenie_vpn/utils/node_parser.dart';

const config = '[Interface]\n'
    'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
    'Address = 172.16.0.2/32\nJc = 4\n\n[Peer]\n'
    'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
    'AllowedIPs = 0.0.0.0/0, ::/0\nReserved = 1, 2, 3\n'
    'Endpoint = 162.159.192.7:4500\n';

void main() {
  test('parses valid AmneziaWG profile', () {
    final node = NodeParser.parse(config);
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.warp);
    expect(node.host, '162.159.192.7');
    expect(node.metadata['engine'], 'amneziawg');
    expect(NodeParser.validationError(node), isNull);
  });
  test('extracts config directly from JSON and base64', () {
    expect(NodeParser.parse(jsonEncode(<String, String>{'config': config})), isNotNull);
    expect(NodeParser.parse(base64Encode(utf8.encode(config))), isNotNull);
  });
  test('rejects every legacy proxy protocol', () {
    expect(NodeParser.parse('vless://id@example.com:443'), isNull);
    expect(NodeParser.parse('vmess://payload'), isNull);
    expect(NodeParser.parse('trojan://secret@example.com:443'), isNull);
  });
  test('rejects malformed reserved tuple', () {
    final node = NodeParser.parse(config.replaceFirst('1, 2, 3', '1, 999'))!;
    expect(NodeParser.validationError(node), contains('Reserved'));
  });
  test('normalizes missing IPv4 address mask', () {
    final node = NodeParser.parse(config.replaceFirst('172.16.0.2/32', '172.16.0.2'))!;
    expect(NodeParser.validationError(node), isNull);
    expect(node.rawConfig, contains('Address = 172.16.0.2/32'));
  });
  test('normalizes both bare IPv4 and IPv6 addresses', () {
    final dual = config.replaceFirst(
      '172.16.0.2/32',
      '172.16.0.2, 2606:4700:110:8765::2',
    );
    final node = NodeParser.parse(dual)!;
    expect(node.rawConfig, contains('172.16.0.2/32'));
    expect(node.rawConfig, contains('2606:4700:110:8765::2/128'));
    expect(NodeParser.validationError(node), isNull);
  });
  test('imports every bundled working WARP profile', () {
    for (final name in <String>[
      'WARP_STR5118.conf',
      'WARP_STR8605.conf',
      'WARP_STR4470.conf',
    ]) {
      final raw = File('assets/warp/$name').readAsStringSync();
      final node = NodeParser.parse(raw, source: 'Стартовый WARP');
      expect(node, isNotNull, reason: name);
      expect(NodeParser.validationError(node!), isNull, reason: name);
      final addressLine = node.rawConfig
          .split('\n')
          .firstWhere((line) => line.trimLeft().toLowerCase().startsWith('address'));
      expect(
        addressLine.split('=').last.split(',').every((item) => item.contains('/')),
        isTrue,
        reason: name,
      );
    }
  });
}
