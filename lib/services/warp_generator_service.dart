import 'dart:convert';
import 'package:http/http.dart' as http;

/// Generates one mobile WARP/AmneziaWG profile without opening a browser or
/// writing a download. The endpoint is the public API of the open-source
/// HereIamGosu/amnezia-config-gen project.
class WarpGeneratorService {
  WarpGeneratorService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _endpoints = <String>[
    'https://valokda-amnezia.vercel.app/api/warp',
  ];

  Future<String> generateOne() async {
    final errors = <String>[];
    for (final endpoint in _endpoints) {
      try {
        final response = await _client.post(
          Uri.parse(endpoint),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'Pokolenie-WARP/1.0.0 (Android)',
          },
          body: jsonEncode(const <String, dynamic>{
            'mode': 'legacy',
            'template': 'warp_amnezia',
            'mobile': true,
            'ipv6': false,
            'persistentKeepalive': 25,
          }),
        ).timeout(const Duration(seconds: 30));
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          errors.add('неизвестный JSON');
          continue;
        }
        if (response.statusCode == 429) {
          errors.add('лимит частоты');
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
          errors.add(decoded['message']?.toString() ?? 'HTTP ${response.statusCode}');
          continue;
        }
        final encoded = decoded['content']?.toString() ?? '';
        if (encoded.isEmpty) {
          errors.add('пустой ответ');
          continue;
        }
        final config = utf8.decode(base64Decode(base64.normalize(encoded))).trim();
        final lower = config.toLowerCase();
        if (!lower.contains('[interface]') || !lower.contains('[peer]') || !lower.contains('privatekey') || !lower.contains('endpoint')) {
          errors.add('неполный конфиг');
          continue;
        }
        return '$config\n';
      } catch (error) {
        errors.add(error.runtimeType.toString());
      }
    }
    throw StateError('Генератор временно недоступен: ${errors.join(', ')}');
  }

  void dispose() => _client.close();
}
