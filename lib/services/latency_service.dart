import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/vpn_core.dart';
import '../models/app_settings.dart';
import '../models/vpn_node.dart';

class LatencyService {
  LatencyService(this.core, {http.Client? client})
    : _client = client ?? http.Client();

  final VpnCore core;
  final http.Client _client;

  static const _connectivityUrls = <String>[
    'https://connectivitycheck.gstatic.com/generate_204',
    'https://www.cloudflare.com/cdn-cgi/trace',
    'https://www.msftconnecttest.com/connecttest.txt',
  ];

  Future<bool> hasBaseInternet(Duration timeout) async {
    final perRequest = Duration(
      milliseconds: (timeout.inMilliseconds ~/ 2).clamp(1200, 5000).toInt(),
    );
    for (final value in _connectivityUrls) {
      try {
        final response = await _client
            .get(
              Uri.parse(value),
              headers: const <String, String>{'Cache-Control': 'no-cache'},
            )
            .timeout(perRequest);
        if (response.statusCode >= 200 && response.statusCode < 500) {
          return true;
        }
      } catch (_) {
        // Try another independent endpoint.
      }
    }
    return false;
  }

  Future<ProbeResult> check(
    VpnNode node,
    Duration timeout, {
    required AppSettings settings,
  }) => core.test(node, timeout, settings: settings);

  void dispose() => _client.close();
}
