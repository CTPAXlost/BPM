import 'dart:convert';

import 'package:http/http.dart' as http;

class WarpGeneratorService {
  WarpGeneratorService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _mirrors = <String>[
    'https://warp3.llimonix.pw/api/generate',
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
                'User-Agent': 'Pokolenie-VPN/0.9.5 (Android)',
              },
              body: jsonEncode(const <String, dynamic>{
                'selectedServices': <String>[],
                'siteMode': 'all',
                'deviceType': 'awg15',
                'endpoint': 'engage.cloudflareclient.com:4500',
                'configFormat': 'wireguard',
                'dnsId': 'cf',
                'ipv6': false,
                'excludeLan': true,
                'persistentKeepalive': 25,
                'customI1Domain': 'google.com',
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 429) {
          errors.add('${Uri.parse(endpoint).host}: ограничение частоты');
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          errors.add('${Uri.parse(endpoint).host}: HTTP ${response.statusCode}');
          continue;
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
          errors.add('${Uri.parse(endpoint).host}: отказ сервера');
          continue;
        }
        final content = decoded['content'];
        if (content is! Map<String, dynamic>) {
          errors.add('${Uri.parse(endpoint).host}: нет конфигурации');
          continue;
        }
        final encoded = content['configBase64']?.toString() ?? '';
        if (encoded.isEmpty) {
          errors.add('${Uri.parse(endpoint).host}: пустая конфигурация');
          continue;
        }
        final config = utf8.decode(base64Decode(encoded)).trim();
        if (!config.toLowerCase().contains('[interface]') ||
            !config.toLowerCase().contains('[peer]')) {
          errors.add('${Uri.parse(endpoint).host}: неверный формат');
          continue;
        }
        return '$config\n';
      } catch (error) {
        errors.add(
          '${Uri.parse(endpoint).host}: ${error.runtimeType}',
        );
      }
    }
    throw StateError(
      'Все зеркала генератора временно недоступны: ${errors.join(', ')}.',
    );
  }

  void dispose() => _client.close();
}
