import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokolenie_vpn/models/vpn_protocol.dart';
import 'package:pokolenie_vpn/utils/node_parser.dart';

void main() {
  test('parses VLESS link', () {
    final node = NodeParser.parse(
      'vless://00000000-0000-0000-0000-000000000000@example.com:443?security=tls&type=ws#France',
    );
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.vless);
    expect(node.port, 443);
  });

  test('parses base64 VMess link', () {
    final payload = base64.encode(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'v': '2',
          'ps': 'Germany',
          'add': 'example.com',
          'port': '443',
          'id': '00000000-0000-0000-0000-000000000000',
          'aid': '0',
          'net': 'ws',
        }),
      ),
    );
    final node = NodeParser.parse('vmess://$payload');
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.vmess);
  });

  test('encodes and parses local WARP profile', () {
    final raw = NodeParser.encodeWarp(<String, dynamic>{
      'name': 'WARP test',
      'endpoint_host': 'engage.cloudflareclient.com',
      'endpoint_port': 2408,
      'private_key': 'private',
    });
    final node = NodeParser.parse(raw);
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.warp);
  });

  test('parses WarpGen AmneziaWG config with UTF-8 BOM', () {
    const raw = '\uFEFF#################################################\n'
        '# Generated with warpgen: https://warpgen.net\n'
        '[Interface]\n'
        'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        'Address = 172.16.0.2/32\n'
        'DNS = 1.1.1.1\n'
        'MTU = 1280\n'
        'Jc = 4\n'
        'Jmin = 40\n'
        'Jmax = 70\n'
        'H1 = 1\n'
        'H2 = 2\n'
        'H3 = 3\n'
        'H4 = 4\n'
        '\n[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Reserved = 1, 2, 3\n'
        'Endpoint = 162.159.192.7:4500\n';
    final node = NodeParser.parse(raw, source: 'WarpGen.net');
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.warp);
    expect(node.host, '162.159.192.7');
    expect(node.port, 4500);
    expect(node.metadata['engine'], 'amneziawg');
    expect(node.metadata['warpgen'], isTrue);
    expect(node.metadata['wg_quick'], contains('Jc = 4'));
    expect(node.metadata['private_key'],
        'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=');
    expect(node.metadata['peer_public_key'],
        'ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=');
    expect(node.metadata['address_v4'], '172.16.0.2/32');
    expect(node.metadata['reserved'], <int>[1, 2, 3]);
    expect(NodeParser.catalogCompatibilityError(node), isNull);
  });

  test('rejects WARP config without required Address', () {
    const raw = '[Interface]\n'
        'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        '\n[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Endpoint = 162.159.192.7:4500\n';
    final node = NodeParser.parse(raw, source: 'Broken WARP');
    expect(node, isNotNull);
    expect(
      NodeParser.catalogCompatibilityError(node!),
      contains('Address'),
    );
  });

  test('accepts official legacy Shadowsocks cipher', () {
    final credentials = base64Url.encode(utf8.encode('aes-256-cfb:legacy-secret')).replaceAll('=', '');
    final node = NodeParser.parse('ss://$credentials@legacy.example:8388#Legacy');
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.shadowsocks);
    expect(NodeParser.catalogCompatibilityError(node), isNull);
  });

  test('accepts whitelist VLESS Reality raw transport', () {
    final node = NodeParser.parse(
      'vless://00000000-0000-0000-0000-000000000123@white.example:443'
      '?type=raw&security=reality&sni=example.com&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA'
      '&flow=xtls-rprx-vision#WHITE-CIDR',
      source: 'Белые списки RU',
      catalogClass: 'whitelist',
    );
    expect(node, isNotNull);
    expect(node!.isWhitelist, isTrue);
    expect(NodeParser.catalogCompatibilityError(node), isNull);
  });

  test('rejects malformed Reality public key before sing-box', () {
    final node = NodeParser.parse(
      'vless://00000000-0000-0000-0000-000000000125@bad-key.example:443'
      '?type=raw&security=reality&sni=example.com&pbk=public-key'
      '&flow=xtls-rprx-vision#BAD-REALITY-KEY',
    );
    expect(node, isNotNull);
    expect(
      NodeParser.catalogCompatibilityError(node!),
      contains('public key'),
    );
  });

  test('rejects unsupported xhttp before it reaches sing-box', () {
    final node = NodeParser.parse(
      'vless://00000000-0000-0000-0000-000000000124@bad.example:443'
      '?type=xhttp&security=tls&sni=bad.example#bad',
    );
    expect(node, isNotNull);
    expect(NodeParser.catalogCompatibilityError(node!), contains('xhttp'));
  });

  test('rejects WARP with malformed Reserved tuple', () {
    const raw = '[Interface]\n'
        'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        'Address = 172.16.0.2/32\n'
        '\n[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Reserved = 1, 999\n'
        'Endpoint = 162.159.192.7:2408\n';
    final node = NodeParser.parse(raw, source: 'Broken Reserved');
    expect(node, isNotNull);
    expect(NodeParser.catalogCompatibilityError(node!), contains('Reserved'));
  });

  test('rejects all-zero WireGuard key', () {
    const raw = '[Interface]\n'
        'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n'
        'Address = 172.16.0.2/32\n'
        '\n[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Endpoint = 162.159.192.7:2408\n';
    final node = NodeParser.parse(raw, source: 'Zero key');
    expect(node, isNotNull);
    expect(NodeParser.catalogCompatibilityError(node!), contains('PrivateKey'));
  });

  test('extracts one WARP config from escaped JSON', () {
    const config = '[Interface]\n'
        'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        'Address = 172.16.0.2/32\n\n'
        '[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Reserved = 1, 2, 3\n'
        'Endpoint = 162.159.192.7:2408\n';
    final wrapped = jsonEncode(<String, dynamic>{
      'profile': <String, dynamic>{'config': config},
      'ignored': '[Interface] incomplete',
    });
    final node = NodeParser.parse(wrapped, source: 'WarpGen.net');
    expect(node, isNotNull);
    expect(node!.metadata['private_key'], isNotEmpty);
    expect(node.metadata['reserved'], <int>[1, 2, 3]);
  });

  test('extracts one WARP config from base64 wrapper', () {
    const config = '[Interface]\n'
        'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        'Address = 172.16.0.2/32\n\n'
        '[Peer]\n'
        'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs = 0.0.0.0/0, ::/0\n'
        'Endpoint = 162.159.192.7:2408\n';
    final encoded = base64.encode(utf8.encode(config));
    final node = NodeParser.parse(encoded, source: 'warp-gen.github.io');
    expect(node, isNotNull);
    expect(node!.protocol, VpnProtocol.warp);
    expect(NodeParser.catalogCompatibilityError(node), isNull);
  });

  test('imports Portal WG config without spaces around equals', () {
    const config = '[Interface]\n'
        'PrivateKey=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=\n'
        'Address=172.16.0.2/32\n'
        'Jc=4\n\n'
        '[Peer]\n'
        'PublicKey=ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=\n'
        'AllowedIPs=0.0.0.0/0,::/0\n'
        'Endpoint=162.159.192.7:2408\n';
    final wrapped = jsonEncode(<String, dynamic>{'config': config});
    final node = NodeParser.parse(wrapped, source: 'Portal WG');
    expect(node, isNotNull);
    expect(node!.metadata['engine'], 'amneziawg');
    expect(NodeParser.catalogCompatibilityError(node), isNull);
  });

}
