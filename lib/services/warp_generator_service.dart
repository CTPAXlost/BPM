import 'dart:convert';

import 'package:http/http.dart' as http;

class WarpGeneratorService {
  WarpGeneratorService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _mirrors = <String>[
    'https://warply3.vercel.app/api/generate',
    'https://warp.llimonix.workers.dev/api/generate',
    'https://getwarp3.netlify.app/api/generate',
  ];

  Future<String> generateOne() async {
    final errors = <String>[];
    for (final endpoint in _mirrors) {
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: const <String, String>{
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(const <String, dynamic>{
                'selectedServices': <String>[],
                'siteMode': 'all',
                'deviceType': 'awg15',
                'endpoint': 'engage.cloudflareclient.com:4500',
                'configFormat': 'wireguard',
                'dnsId': 'cf',
                'ipv6': false,
                'excludeLan': false,
                'persistentKeepalive': 25,
              }),
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode == 429) {
          errors.add('ограничение частоты');
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          errors.add('HTTP ${response.statusCode}');
          continue;
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
          errors.add('отказ сервера');
          continue;
        }
        final content = decoded['content'];
        if (content is! Map<String, dynamic>) {
          errors.add('нет конфигурации');
          continue;
        }
        final encoded = content['configBase64']?.toString() ?? '';
        if (encoded.isEmpty) {
          errors.add('пустая конфигурация');
          continue;
        }
        final config = utf8.decode(base64Decode(encoded)).trim();
        if (!config.toLowerCase().contains('[interface]') ||
            !config.toLowerCase().contains('[peer]')) {
          errors.add('неверный формат');
          continue;
        }
        return '$config\n';
      } catch (error) {
        errors.add(error.runtimeType.toString());
      }
    }
    throw StateError(
      'Все зеркала генератора временно недоступны: ${errors.join(', ')}.',
    );
  }

  void dispose() => _client.close();
}
