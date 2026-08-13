import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class WarpProvisioningService {
  WarpProvisioningService({http.Client? client})
    : _client = client ?? http.Client();

  static const MethodChannel _channel = MethodChannel('app.pokolenie/warpgen');
  static const List<String> _apiVersions = <String>['v0i1909051800', 'v0a977'];
  static const List<String> _endpoints = <String>[
    '162.159.192.1:2408',
    '162.159.192.2:2408',
    '162.159.193.1:2408',
    '162.159.193.2:2408',
    '188.114.96.1:2408',
    '188.114.97.1:2408',
    'engage.cloudflareclient.com:2408',
    'engage.cloudflareclient.com:500',
    'engage.cloudflareclient.com:1701',
    'engage.cloudflareclient.com:4500',
  ];

  final http.Client _client;

  Future<List<String>> generate({int count = 6}) async {
    final keys = await _channel.invokeMapMethod<String, dynamic>(
      'generateKeyPair',
    );
    final privateKey = keys?['privateKey']?.toString() ?? '';
    final publicKey = keys?['publicKey']?.toString() ?? '';
    if (privateKey.isEmpty || publicKey.isEmpty) {
      throw StateError('Android не создал ключевую пару WireGuard.');
    }

    Object? lastError;
    for (final version in _apiVersions) {
      try {
        final uri = Uri.parse('https://api.cloudflareclient.com/$version/reg');
        final response = await _client
            .post(
              uri,
              headers: const <String, String>{
                'User-Agent': 'okhttp/3.12.1',
                'Content-Type': 'application/json; charset=UTF-8',
              },
              body: jsonEncode(<String, dynamic>{
                'install_id': '',
                'tos': DateTime.now().toUtc().toIso8601String(),
                'key': publicKey,
                'fcm_token': '',
                'type': 'Android',
                'locale': 'ru_RU',
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('Cloudflare HTTP ${response.statusCode}');
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final result =
            (decoded['result'] as Map?)?.cast<String, dynamic>() ?? decoded;
        return _buildConfigs(result, privateKey, count);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Регистрация WARP не выполнена: $lastError');
  }

  List<String> _buildConfigs(
    Map<String, dynamic> result,
    String privateKey,
    int count,
  ) {
    final config =
        (result['config'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final interface =
        (config['interface'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final addresses =
        (interface['addresses'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final peers = config['peers'] as List<dynamic>? ?? const <dynamic>[];
    final peer = peers.isEmpty
        ? const <String, dynamic>{}
        : (peers.first as Map).cast<String, dynamic>();
    final peerKey =
        peer['public_key']?.toString() ?? peer['publicKey']?.toString() ?? '';
    final v4 = addresses['v4']?.toString() ?? '';
    final v6 = addresses['v6']?.toString() ?? '';
    if (peerKey.isEmpty || v4.isEmpty) {
      throw const FormatException(
        'Cloudflare вернул неполную WARP-конфигурацию.',
      );
    }
    final address = <String>[
      v4.contains('/') ? v4 : '$v4/32',
      if (v6.isNotEmpty) v6.contains('/') ? v6 : '$v6/128',
    ].join(', ');
    final reserved = _reserved(config['client_id']?.toString());
    final limit = count.clamp(1, _endpoints.length).toInt();
    return <String>[
      for (var index = 0; index < limit; index++)
        '# Pokolenie automatic WARP ${index + 1}\n'
            '[Interface]\n'
            'PrivateKey = $privateKey\n'
            'Address = $address\n'
            'DNS = 1.1.1.1, 1.0.0.1\n'
            'MTU = 1280\n\n'
            '[Peer]\n'
            'PublicKey = $peerKey\n'
            'AllowedIPs = 0.0.0.0/0, ::/0\n'
            'Endpoint = ${_endpoints[index]}\n'
            '${reserved.isEmpty ? '' : 'Reserved = $reserved\n'}'
            'PersistentKeepalive = 25\n',
    ];
  }

  String _reserved(String? clientId) {
    if (clientId == null || clientId.isEmpty) return '';
    try {
      final bytes = base64Decode(clientId);
      return bytes.take(3).join(', ');
    } catch (_) {
      return '';
    }
  }

  void dispose() => _client.close();
}
