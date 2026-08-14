import 'dart:io';

import 'package:flutter/services.dart';

class AwgNetworkStatus {
  const AwgNetworkStatus({
    required this.vpnPresent,
    required this.hasInternetCapability,
    required this.validated,
    this.interfaceName = '',
  });

  factory AwgNetworkStatus.fromMap(Map<Object?, Object?> raw) {
    return AwgNetworkStatus(
      vpnPresent: raw['vpnPresent'] == true,
      hasInternetCapability: raw['hasInternetCapability'] == true,
      validated: raw['validated'] == true,
      interfaceName: raw['interfaceName']?.toString() ?? '',
    );
  }

  final bool vpnPresent;
  final bool hasInternetCapability;
  final bool validated;
  final String interfaceName;
}

class VpnBoundProbe {
  const VpnBoundProbe({
    required this.success,
    required this.latencyMs,
    this.detail = '',
  });

  factory VpnBoundProbe.fromMap(Map<Object?, Object?> raw) {
    return VpnBoundProbe(
      success: raw['success'] == true,
      latencyMs: int.tryParse(raw['latencyMs']?.toString() ?? '') ?? 0,
      detail: raw['detail']?.toString() ?? '',
    );
  }

  final bool success;
  final int latencyMs;
  final String detail;
}

class AwgTrafficStats {
  const AwgTrafficStats({required this.received, required this.sent});

  factory AwgTrafficStats.fromMap(Map<Object?, Object?> raw) {
    return AwgTrafficStats(
      received: int.tryParse(raw['received']?.toString() ?? '') ?? 0,
      sent: int.tryParse(raw['sent']?.toString() ?? '') ?? 0,
    );
  }

  final int received;
  final int sent;
}

class AmneziaWgBridge {
  static const MethodChannel _channel = MethodChannel('app.pokolenie/awg');

  bool get supported => Platform.isAndroid;

  Future<bool> requestPermission() async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  Future<void> start({required String config, String name = 'pokolenie'}) async {
    if (!supported) {
      throw UnsupportedError('AmneziaWG встроен только в Android-сборку.');
    }
    await _channel.invokeMethod<void>('start', <String, dynamic>{
      'config': config,
      'name': _sanitizeName(name),
    });
  }

  Future<void> stop() async {
    if (!supported) return;
    await _channel.invokeMethod<void>('stop');
  }

  Future<String> state() async {
    if (!supported) return 'unsupported';
    return await _channel.invokeMethod<String>('state') ?? 'unknown';
  }

  Future<int> lastHandshakeSeconds() async {
    if (!supported) return -3;
    return await _channel.invokeMethod<int>('lastHandshake') ?? -2;
  }

  Future<AwgTrafficStats> statistics() async {
    if (!supported) return const AwgTrafficStats(received: 0, sent: 0);
    final raw = await _channel.invokeMapMethod<Object?, Object?>('statistics');
    return AwgTrafficStats.fromMap(raw ?? const <Object?, Object?>{});
  }

  Future<AwgNetworkStatus> networkStatus() async {
    if (!supported) {
      return const AwgNetworkStatus(
        vpnPresent: false,
        hasInternetCapability: false,
        validated: false,
      );
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>('networkStatus');
    return AwgNetworkStatus.fromMap(raw ?? const <Object?, Object?>{});
  }

  Future<AwgNetworkStatus> baseNetworkStatus() async {
    if (!supported) {
      return const AwgNetworkStatus(
        vpnPresent: false,
        hasInternetCapability: false,
        validated: false,
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>('baseNetworkStatus');
    return AwgNetworkStatus.fromMap(raw ?? const <Object?, Object?>{});
  }

  Future<VpnBoundProbe> probeBaseNetwork() async {
    if (!supported) {
      return const VpnBoundProbe(
        success: false,
        latencyMs: 0,
        detail: 'Base-network probe unsupported.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>('probeBaseNetwork');
    return VpnBoundProbe.fromMap(raw ?? const <Object?, Object?>{});
  }

  Future<VpnBoundProbe> probeVpnNetwork() async {
    if (!supported) {
      return const VpnBoundProbe(
        success: false,
        latencyMs: 0,
        detail: 'VPN-bound probe unsupported.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>('probeVpnNetwork');
    return VpnBoundProbe.fromMap(raw ?? const <Object?, Object?>{});
  }

  String _sanitizeName(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_=+.-]'), '-');
    if (safe.isEmpty) return 'pokolenie';
    return safe.length <= 15 ? safe : safe.substring(0, 15);
  }
}
