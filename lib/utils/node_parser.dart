import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';

/// Strict WireGuard/AmneziaWG parser. Every other VPN protocol is rejected.
class NodeParser {
  static bool looksLikeWgQuick(String value) {
    final lower = value.trim().toLowerCase();
    return lower.contains('[interface]') && lower.contains('[peer]');
  }

  static String? extractSingleWgQuick(String input) {
    final direct = _normaliseText(input);
    if (looksLikeWgQuick(direct)) return _sliceConfig(direct);
    try {
      final decoded = jsonDecode(input);
      final values = <String>[];
      void walk(dynamic value) {
        if (value is String) values.add(value);
        if (value is List) for (final item in value) walk(item);
        if (value is Map) for (final item in value.values) walk(item);
      }
      walk(decoded);
      for (final value in values) {
        final candidate = _normaliseText(value);
        if (looksLikeWgQuick(candidate)) return _sliceConfig(candidate);
      }
    } catch (_) {}
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= 32) {
      try {
        final candidate = _normaliseText(utf8.decode(base64Decode(base64.normalize(compact))));
        if (looksLikeWgQuick(candidate)) return _sliceConfig(candidate);
      } catch (_) {}
    }
    return null;
  }

  static VpnNode? parse(String input, {String source = ''}) {
    final extracted = extractSingleWgQuick(input);
    if (extracted == null) return null;
    final config = _normaliseAddresses(extracted);
    final sections = _sections(config);
    final interface = sections['interface'];
    final peer = sections['peer'];
    if (interface == null || peer == null) return null;
    final endpoint = _parseEndpoint(peer['endpoint'] ?? '');
    if (endpoint == null) return null;
    final awg = <String>['j', 'jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4', 'i1', 'i2', 'i3', 'i4', 'i5'].any(interface.containsKey);
    final canonical = '${config.trim()}\n';
    return VpnNode(
      id: sha256.convert(utf8.encode(canonical)).toString(),
      name: awg ? 'WARP / AmneziaWG' : 'WARP / WireGuard',
      protocol: VpnProtocol.warp,
      rawConfig: canonical,
      host: endpoint.$1,
      port: endpoint.$2,
      transport: awg ? 'amneziawg' : 'wireguard',
      source: source,
      metadata: <String, dynamic>{'wg_quick': canonical, 'engine': awg ? 'amneziawg' : 'wireguard'},
    );
  }

  static String? validationError(VpnNode node) {
    final extracted = extractSingleWgQuick(node.metadata['wg_quick']?.toString() ?? node.rawConfig);
    if (extracted == null) return 'нет секций [Interface] и [Peer]';
    final config = _normaliseAddresses(extracted);
    final sections = _sections(config);
    final interface = sections['interface'] ?? const <String, String>{};
    final peer = sections['peer'] ?? const <String, String>{};
    if (!_validKey(interface['privatekey'])) return 'неверный PrivateKey';
    if (!_validKey(peer['publickey'])) return 'неверный PublicKey';
    final addresses = interface['address']?.split(',') ?? const <String>[];
    if (addresses.isEmpty || addresses.any((e) => !e.trim().contains('/'))) return 'не удалось определить маску Address';
    if (_parseEndpoint(peer['endpoint'] ?? '') == null) return 'неверный Endpoint';
    if ((peer['allowedips'] ?? '').trim().isEmpty) return 'нет AllowedIPs';
    final reserved = peer['reserved'];
    if (reserved != null) {
      final bytes = reserved.split(',').map((e) => int.tryParse(e.trim())).toList();
      if (bytes.length != 3 || bytes.any((e) => e == null || e < 0 || e > 255)) return 'Reserved должен содержать три байта';
    }
    return null;
  }

  static bool isCompatible(VpnNode node) => validationError(node) == null;

  static String _normaliseText(String value) => value.replaceAll(r'\n', '\n').replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  static String _sliceConfig(String text) => '${text.substring(text.toLowerCase().indexOf('[interface]')).trim()}\n';

  /// Portal WG and several Amnezia generators intentionally emit bare tunnel
  /// addresses. WireGuard treats these as host addresses, so add the canonical
  /// host prefix instead of rejecting an otherwise valid profile.
  static String _normaliseAddresses(String config) {
    var inInterface = false;
    final output = <String>[];
    for (final raw in config.split('\n')) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        inInterface = trimmed.toLowerCase() == '[interface]';
      }
      final equals = raw.indexOf('=');
      if (inInterface && equals > 0 && raw.substring(0, equals).trim().toLowerCase() == 'address') {
        final indent = raw.substring(0, raw.length - raw.trimLeft().length);
        final addresses = raw.substring(equals + 1).split(',').map((item) {
          final address = item.trim();
          if (address.isEmpty || address.contains('/')) return address;
          return address.contains(':') ? '$address/128' : '$address/32';
        }).where((item) => item.isNotEmpty).join(', ');
        output.add('${indent}Address = $addresses');
      } else {
        output.add(raw);
      }
    }
    return '${output.join('\n').trim()}\n';
  }

  static Map<String, Map<String, String>> _sections(String config) {
    final result = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (final raw in config.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = result.putIfAbsent(line.substring(1, line.length - 1).toLowerCase(), () => <String, String>{});
        continue;
      }
      final equals = line.indexOf('=');
      if (current != null && equals > 0) current[line.substring(0, equals).trim().toLowerCase()] = line.substring(equals + 1).trim();
    }
    return result;
  }

  static (String, int)? _parseEndpoint(String value) {
    final endpoint = value.trim();
    String host;
    String portText;
    if (endpoint.startsWith('[')) {
      final end = endpoint.indexOf(']');
      if (end < 2 || end + 2 >= endpoint.length || endpoint[end + 1] != ':') return null;
      host = endpoint.substring(1, end);
      portText = endpoint.substring(end + 2);
    } else {
      final colon = endpoint.lastIndexOf(':');
      if (colon <= 0) return null;
      host = endpoint.substring(0, colon);
      portText = endpoint.substring(colon + 1);
    }
    final port = int.tryParse(portText);
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    return (host, port);
  }

  static bool _validKey(String? value) {
    if (value == null) return false;
    try { return base64Decode(value.trim()).length == 32; } catch (_) { return false; }
  }
}
