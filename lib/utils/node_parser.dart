import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';

class NodeParser {
  static final RegExp _linkPattern = RegExp(
    r'''(?:(?:vless|vmess|trojan|ss|shadowsocks|hysteria2|hysteria|hy2|tuic)://[^\s"'<>]+)''',
    caseSensitive: false,
  );

  static List<String> extractLinks(String raw) {
    final candidates = <String>{};
    final normalized = _tryDecodeSubscription(raw);
    for (final match in _linkPattern.allMatches(normalized)) {
      var value = match.group(0)!.trim();
      value = value.replaceAll(RegExp(r'[),;]+$'), '');
      if (value.isNotEmpty) candidates.add(value);
    }
    return candidates.toList(growable: false);
  }

  static bool looksLikeWgQuick(String raw) {
    final lower = raw.replaceFirst('\uFEFF', '').toLowerCase();
    final hasInterface = RegExp(
      r'^\s*\[interface\]\s*$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(lower);
    final hasPeer = RegExp(
      r'^\s*\[peer\]\s*$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(lower);
    return hasInterface && hasPeer;
  }

  /// Extracts exactly one wg-quick profile from plain text, escaped JSON,
  /// HTML snippets or a base64-wrapped value returned by a generator site.
  static String? extractSingleWgQuick(String raw) {
    final queue = <String>[raw];
    final seen = <String>{};
    var inspected = 0;
    while (queue.isNotEmpty && inspected < 80) {
      final candidate = queue.removeAt(0).trim();
      if (candidate.isEmpty || !seen.add(candidate)) continue;
      inspected += 1;

      final extracted = _extractWgQuickBlock(candidate);
      if (extracted != null) return extracted;

      final unescaped = candidate
          .replaceAll(r'\r\n', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t')
          .replaceAll('&lbrack;', '[')
          .replaceAll('&rbrack;', ']')
          .replaceAll('&#91;', '[')
          .replaceAll('&#93;', ']')
          .replaceAll('&equals;', '=')
          .replaceAll('&amp;', '&');
      if (unescaped != candidate) queue.add(unescaped);

      try {
        _collectEmbeddedStrings(jsonDecode(candidate), queue);
      } catch (_) {
        // The candidate is not JSON.
      }

      final compact = candidate.replaceAll(RegExp(r'\s+'), '');
      if (compact.length >= 80 &&
          compact.length <= 200000 &&
          RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) {
        try {
          final decoded = utf8.decode(
            base64.decode(_normalizeBase64(compact)),
            allowMalformed: false,
          );
          queue.add(decoded);
        } catch (_) {
          // Not a UTF-8 base64 payload.
        }
      }
    }
    return null;
  }

  static void _collectEmbeddedStrings(dynamic value, List<String> output) {
    if (value is String) {
      if (value.trim().isNotEmpty) output.add(value);
      return;
    }
    if (value is List<dynamic>) {
      for (final item in value) {
        _collectEmbeddedStrings(item, output);
      }
      return;
    }
    if (value is Map<dynamic, dynamic>) {
      for (final item in value.values) {
        _collectEmbeddedStrings(item, output);
      }
    }
  }

  static String? _extractWgQuickBlock(String raw) {
    final allowed = <String>{
      'privatekey', 'address', 'dns', 'mtu', 'listenport', 'table', 'fwmark',
      'jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4',
      'h1', 'h2', 'h3', 'h4', 'i1', 'i2', 'i3', 'i4', 'i5',
      'publickey', 'presharedkey', 'allowedips', 'endpoint',
      'persistentkeepalive', 'reserved',
    };
    final output = <String>[];
    var section = '';
    var sawInterface = false;
    var sawPeer = false;
    for (final rawLine in raw.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.toLowerCase() == '[interface]') {
        if (sawInterface) break;
        sawInterface = true;
        section = 'interface';
        output.add('[Interface]');
        continue;
      }
      if (line.toLowerCase() == '[peer]' && sawInterface) {
        if (sawPeer) break;
        sawPeer = true;
        section = 'peer';
        output..add('')..add('[Peer]');
        continue;
      }
      if (section.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        if (sawPeer) break;
        continue;
      }
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      if (allowed.contains(key)) output.add(line);
    }
    if (!sawInterface || !sawPeer) return null;
    final result = output.join('\n').trim();
    for (final field in const <String>[
      'PrivateKey',
      'Address',
      'PublicKey',
      'AllowedIPs',
      'Endpoint',
    ]) {
      if (_wgValue(result, field) == null) return null;
    }
    return '$result\n';
  }

  static String _tryDecodeSubscription(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('://') || trimmed.contains('\n')) return trimmed;
    try {
      final decoded = utf8.decode(base64.decode(_normalizeBase64(trimmed)));
      if (decoded.contains('://')) return decoded;
    } catch (_) {
      // Plain text is returned below.
    }
    return trimmed;
  }

  static String _normalizeBase64(String value) {
    var normalized = value
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll(RegExp(r'\s+'), '');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return normalized;
  }

  static VpnNode? parse(
    String raw, {
    String source = '',
    String catalogClass = 'regular',
    String catalogSubtype = '',
  }) {
    final normalized = raw.replaceFirst('\uFEFF', '').trim();
    final wgQuick = extractSingleWgQuick(normalized);
    if (wgQuick != null) {
      try {
        final node = _parseWgQuick(wgQuick, source);
        if (node == null) return null;
        return node.copyWith(
          metadata: <String, dynamic>{
            ...node.metadata,
            'catalog_class': catalogClass,
            if (catalogSubtype.isNotEmpty) 'catalog_subtype': catalogSubtype,
          },
        );
      } catch (_) {
        return null;
      }
    }
    final protocol = VpnProtocol.fromUri(normalized);
    if (protocol == null) return null;
    try {
      final node = switch (protocol) {
        VpnProtocol.vless => _parseUri(normalized, protocol, source),
        VpnProtocol.trojan => _parseUri(normalized, protocol, source),
        VpnProtocol.hysteria2 => _parseUri(normalized, protocol, source),
        VpnProtocol.tuic => _parseUri(normalized, protocol, source),
        VpnProtocol.shadowsocks => _parseShadowsocks(normalized, source),
        VpnProtocol.vmess => _parseVmess(normalized, source),
        VpnProtocol.warp => _parseWarp(normalized, source),
      };
      if (node == null) return null;
      return node.copyWith(
        metadata: <String, dynamic>{
          ...node.metadata,
          'catalog_class': catalogClass,
          if (catalogSubtype.isNotEmpty) 'catalog_subtype': catalogSubtype,
          if (catalogClass == 'whitelist') 'special_class': 'whitelist',
        },
      );
    } catch (_) {
      return null;
    }
  }

  static VpnNode? _parseUri(
    String raw,
    VpnProtocol protocol,
    String source,
  ) {
    final uri = Uri.parse(raw);
    if (uri.host.isEmpty || !uri.hasPort || uri.port <= 0) return null;
    final name = _decodeName(uri.fragment, protocol.label);
    final transport = uri.queryParameters['type'] ??
        uri.queryParameters['network'] ??
        (protocol == VpnProtocol.hysteria2 || protocol == VpnProtocol.tuic
            ? 'QUIC'
            : 'TCP');
    final country = _guessCountry(name);
    return VpnNode(
      id: _id(raw),
      name: name,
      protocol: protocol,
      rawConfig: raw,
      host: uri.host,
      port: uri.port,
      transport: transport,
      countryCode: country.$1,
      countryName: country.$2,
      source: source,
      metadata: <String, dynamic>{
        'query': uri.queryParameters,
        'user_info': uri.userInfo,
      },
    );
  }

  static VpnNode? _parseShadowsocks(String raw, String source) {
    final value = raw.replaceFirst(
      RegExp(r'^shadowsocks://', caseSensitive: false),
      'ss://',
    );
    final uri = Uri.parse(value);
    String host = uri.host;
    int port = uri.hasPort ? uri.port : 0;
    String method = '';
    String password = '';

    if (host.isNotEmpty && port > 0) {
      var userInfo = uri.userInfo;
      if (!userInfo.contains(':')) {
        try {
          userInfo = utf8.decode(base64.decode(_normalizeBase64(userInfo)));
        } catch (_) {}
      }
      final split = userInfo.indexOf(':');
      if (split > 0) {
        method = userInfo.substring(0, split);
        password = userInfo.substring(split + 1);
      }
    } else {
      final payload = value
          .substring('ss://'.length)
          .split('#')
          .first
          .split('?')
          .first;
      final decoded = utf8.decode(base64.decode(_normalizeBase64(payload)));
      final at = decoded.lastIndexOf('@');
      final colon = decoded.lastIndexOf(':');
      if (at <= 0 || colon <= at) return null;
      final auth = decoded.substring(0, at);
      final authColon = auth.indexOf(':');
      if (authColon <= 0) return null;
      method = auth.substring(0, authColon);
      password = auth.substring(authColon + 1);
      host = decoded.substring(at + 1, colon);
      port = int.tryParse(decoded.substring(colon + 1)) ?? 0;
    }
    if (host.isEmpty || port <= 0 || method.isEmpty || password.isEmpty) {
      return null;
    }
    final name = _decodeName(uri.fragment, 'Shadowsocks');
    final country = _guessCountry(name);
    return VpnNode(
      id: _id(raw),
      name: name,
      protocol: VpnProtocol.shadowsocks,
      rawConfig: raw,
      host: host,
      port: port,
      transport: 'TCP/UDP',
      countryCode: country.$1,
      countryName: country.$2,
      source: source,
      metadata: <String, dynamic>{
        'method': method,
        'password': password,
        'query': uri.queryParameters,
        if ((uri.queryParameters['plugin'] ?? '').isNotEmpty)
          'plugin': uri.queryParameters['plugin'],
      },
    );
  }

  static VpnNode? _parseVmess(String raw, String source) {
    final encoded = raw.substring(raw.indexOf('://') + 3).trim();
    final decoded = utf8.decode(base64.decode(_normalizeBase64(encoded)));
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    final host = data['add']?.toString() ?? '';
    final port = int.tryParse(data['port']?.toString() ?? '') ?? 0;
    if (host.isEmpty || port <= 0) return null;
    final candidateName = data['ps']?.toString().trim() ?? '';
    final name = candidateName.isNotEmpty ? candidateName : 'VMess';
    final country = _guessCountry(name);
    return VpnNode(
      id: _id(raw),
      name: name,
      protocol: VpnProtocol.vmess,
      rawConfig: raw,
      host: host,
      port: port,
      transport: data['net']?.toString() ?? 'tcp',
      countryCode: country.$1,
      countryName: country.$2,
      source: source,
      metadata: data,
    );
  }

  static VpnNode? _parseWarp(String raw, String source) {
    if (looksLikeWgQuick(raw)) {
      return _parseWgQuick(raw, source);
    }
    if (!raw.toLowerCase().startsWith('warp://')) return null;
    final encoded = raw.substring('warp://'.length);
    final data = jsonDecode(
      utf8.decode(base64Url.decode(_normalizeBase64(encoded))),
    ) as Map<String, dynamic>;
    final host =
        data['endpoint_host']?.toString() ?? 'engage.cloudflareclient.com';
    final port = int.tryParse(data['endpoint_port']?.toString() ?? '') ?? 2408;
    return VpnNode(
      id: _id(raw),
      name: data['name']?.toString() ?? 'Cloudflare WARP',
      protocol: VpnProtocol.warp,
      rawConfig: raw,
      host: host,
      port: port,
      transport: data['engine'] == 'amneziawg'
          ? 'AmneziaWG / UDP'
          : 'WireGuard / UDP',
      countryCode: 'CF',
      countryName: 'Cloudflare',
      source: source,
      metadata: data,
    );
  }

  static VpnNode? _parseWgQuick(String raw, String source) {
    final normalized = _normalizeWgQuickConfig(raw);
    final endpointValue = _wgValue(normalized, 'Endpoint');
    if (endpointValue == null) return null;
    final parsedEndpoint = _parseEndpoint(endpointValue);
    if (parsedEndpoint == null) return null;

    final lower = normalized.toLowerCase();
    final isWarpGen = lower.contains('warpgen.net') ||
        lower.contains('warp-gen1.vercel.app') ||
        lower.contains('generated with warpgen') ||
        source.toLowerCase().contains('warpgen');
    final isAwg = RegExp(
      r'^\s*(?:jc|jmin|jmax|s1|s2|s3|s4|h1|h2|h3|h4|i1|i2|i3|i4|i5)\s*=',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(normalized);
    final addressValues = (_wgValue(normalized, 'Address') ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    var addressV4 = '';
    var addressV6 = '';
    for (final value in addressValues) {
      if (value.contains(':')) {
        addressV6 = addressV6.isEmpty ? value : addressV6;
      } else {
        addressV4 = addressV4.isEmpty ? value : addressV4;
      }
    }
    final reserved = _parseWgReserved(_wgValue(normalized, 'Reserved'));
    final allowedIps = (_wgValue(normalized, 'AllowedIPs') ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final mtu = int.tryParse(_wgValue(normalized, 'MTU') ?? '') ?? 1280;
    final name = isWarpGen
        ? 'WarpGen WARP'
        : (isAwg ? 'WARP / AmneziaWG' : 'WARP / WireGuard');
    return VpnNode(
      id: _id(normalized),
      name: name,
      protocol: VpnProtocol.warp,
      rawConfig: normalized,
      host: parsedEndpoint.$1,
      port: parsedEndpoint.$2,
      transport: isAwg ? 'AmneziaWG / UDP' : 'WireGuard / UDP',
      countryCode: 'CF',
      countryName: 'Cloudflare',
      source: source.isEmpty
          ? (isWarpGen ? 'WarpGen.net' : 'Импорт WireGuard')
          : source,
      metadata: <String, dynamic>{
        'wg_quick': normalized,
        'engine': isAwg ? 'amneziawg' : 'wireguard',
        'warpgen': isWarpGen,
        'mtu': mtu,
        'private_key': _wgValue(normalized, 'PrivateKey') ?? '',
        'address_v4': addressV4,
        'address_v6': addressV6,
        'peer_public_key': _wgValue(normalized, 'PublicKey') ?? '',
        'allowed_ips': allowedIps,
        'reserved': reserved ?? const <int>[],
        'endpoint_host': parsedEndpoint.$1,
        'endpoint_port': parsedEndpoint.$2,
        if ((_wgValue(normalized, 'DNS') ?? '').isNotEmpty)
          'dns': _wgValue(normalized, 'DNS'),
      },
    );
  }

  static String _normalizeWgQuickConfig(String raw) {
    final lines = raw
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final separator = line.indexOf('=');
      if (separator <= 0 ||
          line.substring(0, separator).trim().toLowerCase() != 'address') {
        continue;
      }
      final addresses = line
          .substring(separator + 1)
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) {
            if (value.contains('/')) return value;
            return value.contains(':') ? '$value/128' : '$value/32';
          })
          .join(', ');
      lines[index] = 'Address = $addresses';
    }
    return lines.join('\n').trim();
  }

  static String? _wgValue(String raw, String field) {
    final match = RegExp(
      '^\\s*${RegExp.escape(field)}\\s*=\\s*(.+?)\\s*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(raw);
    return match?.group(1)?.trim();
  }

  static List<int>? _parseWgReserved(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <int>[];
    final values = raw
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList(growable: false);
    if (values.length != 3 ||
        values.any((value) => value == null || value < 0 || value > 255)) {
      return null;
    }
    return values.cast<int>();
  }

  static bool _validWireGuardKey(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^[A-Za-z0-9+/_-]{43}={0,2}$').hasMatch(trimmed)) {
      return false;
    }
    try {
      final bytes = base64.decode(_normalizeBase64(trimmed));
      return bytes.length == 32 && bytes.any((value) => value != 0);
    } on FormatException {
      return false;
    }
  }

  static (String, int)? _parseEndpoint(String value) {
    final bracketed = RegExp(r'^\[([^]]+)]:(\d+)$').firstMatch(value);
    if (bracketed != null) {
      final port = int.tryParse(bracketed.group(2)!);
      if (port == null || port <= 0 || port > 65535) return null;
      return (bracketed.group(1)!, port);
    }
    final colon = value.lastIndexOf(':');
    if (colon <= 0 || colon == value.length - 1) return null;
    final host = value.substring(0, colon).trim();
    final port = int.tryParse(value.substring(colon + 1).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    return (host, port);
  }

  /// Returns null when the profile is safe to expose in the public catalog.
  /// The check deliberately rejects transports that the bundled mobile parser
  /// cannot import reliably, instead of showing a profile that fails only when
  /// the user presses Connect.
  static String? catalogCompatibilityError(VpnNode node) {
    if (node.host.trim().isEmpty) return 'Пустой адрес сервера';
    if (node.port <= 0 || node.port > 65535) return 'Некорректный порт';

    if (node.protocol == VpnProtocol.warp) {
      if (!looksLikeWgQuick(node.rawConfig)) return 'Некорректный WARP';
      for (final field in const <String>[
        'PrivateKey',
        'Address',
        'PublicKey',
        'AllowedIPs',
        'Endpoint',
      ]) {
        if ((_wgValue(node.rawConfig, field) ?? '').isEmpty) {
          return 'WARP без обязательного поля $field';
        }
      }
      if (!_validWireGuardKey(_wgValue(node.rawConfig, 'PrivateKey') ?? '')) {
        return 'WARP с некорректным PrivateKey';
      }
      if (!_validWireGuardKey(_wgValue(node.rawConfig, 'PublicKey') ?? '')) {
        return 'WARP с некорректным PublicKey';
      }
      final reservedRaw = _wgValue(node.rawConfig, 'Reserved');
      if (reservedRaw != null && _parseWgReserved(reservedRaw) == null) {
        return 'WARP с некорректным Reserved';
      }
      final address = _wgValue(node.rawConfig, 'Address') ?? '';
      if (!address.split(',').any((value) => value.trim().contains('/'))) {
        return 'WARP с некорректным Address';
      }
      return null;
    }

    final queryRaw = node.metadata['query'];
    final query = queryRaw is Map
        ? queryRaw.map((key, value) => MapEntry(key.toString(), value.toString()))
        : const <String, String>{};

    if (node.protocol == VpnProtocol.vmess) {
      final id = node.metadata['id']?.toString().trim() ?? '';
      if (!_isUuid(id)) return 'VMess с некорректным UUID';
      final cipher = (node.metadata['scy'] ?? 'auto').toString().toLowerCase().trim();
      const supported = <String>{'auto', 'none', 'zero', 'aes-128-gcm', 'chacha20-poly1305'};
      if (cipher.isNotEmpty && !supported.contains(cipher)) {
        return 'VMess cipher $cipher не поддерживается';
      }
    }

    if (node.protocol == VpnProtocol.vless ||
        node.protocol == VpnProtocol.trojan ||
        node.protocol == VpnProtocol.hysteria2 ||
        node.protocol == VpnProtocol.tuic) {
      final userInfo = node.metadata['user_info']?.toString().trim() ?? '';
      if (userInfo.isEmpty) return '${node.protocol.label} без ключа доступа';
      if (node.protocol == VpnProtocol.vless && !_isUuid(Uri.decodeComponent(userInfo))) {
        return 'VLESS с некорректным UUID';
      }
      if (node.protocol == VpnProtocol.tuic) {
        final decoded = Uri.decodeComponent(userInfo);
        final separator = decoded.indexOf(':');
        if (separator <= 0 ||
            !_isUuid(decoded.substring(0, separator)) ||
            decoded.substring(separator + 1).isEmpty) {
          return 'TUIC с некорректным UUID или паролем';
        }
      }
    }

    if (node.protocol == VpnProtocol.shadowsocks) {
      final plugin = (node.metadata['plugin'] ?? query['plugin'] ?? '').toString().trim();
      if (plugin.isNotEmpty) return 'Shadowsocks plugin пока не поддерживается';
      final method = node.metadata['method']?.toString().toLowerCase().trim() ?? '';
      const supportedMethods = <String>{
        'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm',
        'chacha20-ietf-poly1305', 'xchacha20-ietf-poly1305',
        '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm',
        '2022-blake3-chacha20-poly1305',
        'aes-128-ctr', 'aes-192-ctr', 'aes-256-ctr',
        'aes-128-cfb', 'aes-192-cfb', 'aes-256-cfb',
        'rc4-md5', 'chacha20-ietf', 'xchacha20', 'none',
      };
      if (!supportedMethods.contains(method)) {
        return 'Метод Shadowsocks $method не поддерживается';
      }
      return null;
    }

    if (node.protocol == VpnProtocol.hysteria2 || node.protocol == VpnProtocol.tuic) {
      final sni = (query['sni'] ?? node.host).trim();
      if (!_validServerName(sni)) return 'Некорректный SNI';
      return null;
    }

    final transport = (query['type'] ?? query['network'] ?? node.transport)
        .toLowerCase()
        .trim();
    const supportedTransports = <String>{
      '', 'tcp', 'raw', 'ws', 'websocket', 'grpc', 'http', 'h2', 'httpupgrade',
    };
    if (!supportedTransports.contains(transport)) {
      return 'Транспорт $transport не поддерживается sing-box ядром приложения';
    }
    final headerType = (query['headerType'] ?? query['header_type'] ?? '').toLowerCase().trim();
    if (headerType.isNotEmpty && headerType != 'none') {
      return 'TCP headerType $headerType не поддерживается';
    }

    final security = (query['security'] ?? '').toLowerCase().trim();
    if (!const <String>{'', 'none', 'tls', 'reality'}.contains(security)) {
      return 'Security $security не поддерживается';
    }
    if (node.protocol == VpnProtocol.vless) {
      final encryption = (query['encryption'] ?? 'none').toLowerCase().trim();
      if (encryption.isNotEmpty && encryption != 'none') {
        return 'VLESS encryption должен быть none';
      }
      final flow = (query['flow'] ?? '').toLowerCase().trim();
      if (flow.isNotEmpty && flow != 'xtls-rprx-vision') {
        return 'VLESS flow $flow не поддерживается';
      }
      if (flow.isNotEmpty && !const <String>{'', 'tcp', 'raw'}.contains(transport)) {
        return 'VLESS Vision работает только через TCP/raw';
      }
    }
    if (security == 'tls' || security == 'reality') {
      final sni = (query['sni'] ?? query['serverName'] ?? '').trim();
      if (sni.isEmpty || !_validServerName(sni)) return 'TLS/Reality без корректного SNI';
    }
    if (security == 'reality') {
      final publicKey = (query['pbk'] ?? query['publicKey'] ?? '').trim();
      if (!_validRealityPublicKey(publicKey)) {
        return 'Reality с некорректным public key';
      }
      final shortId = (query['sid'] ?? query['shortId'] ?? '').trim();
      if (shortId.isNotEmpty &&
          (!RegExp(r'^[0-9a-fA-F]{2,16}$').hasMatch(shortId) || shortId.length.isOdd)) {
        return 'Reality с некорректным short id';
      }
    }
    return null;
  }

  static bool _validRealityPublicKey(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}={0,1}$').hasMatch(value)) return false;
    try {
      final normalized = base64Url.normalize(value);
      return base64Url.decode(normalized).length == 32;
    } on FormatException {
      return false;
    }
  }

  static bool _validServerName(String value) {
    if (value.isEmpty || value.length > 253 || value.contains('://') || value.contains(' ')) {
      return false;
    }
    if (RegExp(r'^\[[0-9a-fA-F:]+\]$').hasMatch(value)) return true;
    if (RegExp(r'^[0-9.]+$').hasMatch(value)) return true;
    return RegExp(r'^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
        .hasMatch(value);
  }

  static bool isCatalogCompatible(VpnNode node) =>
      catalogCompatibilityError(node) == null;

  static bool _isUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value.trim());

  static String encodeWarp(Map<String, dynamic> data) {
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode(data)))
        .replaceAll('=', '');
    return 'warp://$encoded';
  }

  static String _decodeName(String fragment, String fallback) {
    if (fragment.isEmpty) return fallback;
    try {
      final decoded = Uri.decodeComponent(fragment)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return decoded.isEmpty ? fallback : decoded;
    } catch (_) {
      return fragment;
    }
  }

  static String _id(String raw) =>
      sha256.convert(utf8.encode(raw)).toString().substring(0, 20);

  static (String, String) _guessCountry(String name) {
    final lower = name.toLowerCase();
    const countries = <String, (String, String)>{
      'герман': ('DE', 'Германия'),
      'germany': ('DE', 'Германия'),
      'франц': ('FR', 'Франция'),
      'france': ('FR', 'Франция'),
      'нидерланд': ('NL', 'Нидерланды'),
      'netherlands': ('NL', 'Нидерланды'),
      'финлянд': ('FI', 'Финляндия'),
      'finland': ('FI', 'Финляндия'),
      'сша': ('US', 'США'),
      'united states': ('US', 'США'),
      'usa': ('US', 'США'),
      'гонконг': ('HK', 'Гонконг'),
      'hong kong': ('HK', 'Гонконг'),
      'сингапур': ('SG', 'Сингапур'),
      'singapore': ('SG', 'Сингапур'),
      'казахстан': ('KZ', 'Казахстан'),
      'итал': ('IT', 'Италия'),
      'норвег': ('NO', 'Норвегия'),
      'швец': ('SE', 'Швеция'),
      'польш': ('PL', 'Польша'),
      'турц': ('TR', 'Турция'),
      'япон': ('JP', 'Япония'),
      'канада': ('CA', 'Канада'),
      'росси': ('RU', 'Россия'),
      'украин': ('UA', 'Украина'),
      'швейцар': ('CH', 'Швейцария'),
      'великобрит': ('GB', 'Великобритания'),
      'united kingdom': ('GB', 'Великобритания'),
    };
    for (final entry in countries.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    final emoji = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(name)?.group(0);
    if (emoji != null) {
      final runes = emoji.runes.toList();
      if (runes.length == 2) {
        final code = String.fromCharCodes(
          runes.map((value) => value - 127397),
        );
        return (code, code);
      }
    }
    return ('', '');
  }
}
