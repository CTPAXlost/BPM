import '../models/app_settings.dart';
import '../models/vpn_node.dart';

enum VpnCoreState {
  disconnected,
  preparing,
  connecting,
  connected,
  disconnecting,
  error,
}

enum ProbeKind { urlTest, configValidation, connectedTunnel }

class TrafficSnapshot {
  const TrafficSnapshot({
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.totalDownloaded = 0,
    this.totalUploaded = 0,
  });

  final int downloadSpeed;
  final int uploadSpeed;
  final int totalDownloaded;
  final int totalUploaded;
}

class ProbeResult {
  const ProbeResult._({
    required this.success,
    required this.definitive,
    required this.kind,
    this.latencyMs,
    this.detail = '',
  });

  const ProbeResult.urlTestSuccess(
    int latencyMs, {
    String detail = 'Профиль ответил на URL Test без запуска VPN.',
  }) : this._(
         success: true,
         definitive: true,
         kind: ProbeKind.urlTest,
         latencyMs: latencyMs,
         detail: detail,
       );

  const ProbeResult.configValid({
    String detail = 'Структура конфигурации корректна.',
  }) : this._(
         success: true,
         definitive: true,
         kind: ProbeKind.configValidation,
         detail: detail,
       );

  const ProbeResult.connectedTunnelSuccess(
    int latencyMs, {
    String detail = 'Интернет через подключённый VPN подтверждён.',
  }) : this._(
         success: true,
         definitive: true,
         kind: ProbeKind.connectedTunnel,
         latencyMs: latencyMs,
         detail: detail,
       );

  const ProbeResult.failure(
    String detail, {
    ProbeKind kind = ProbeKind.urlTest,
    bool definitive = true,
  }) : this._(
         success: false,
         definitive: definitive,
         kind: kind,
         detail: detail,
       );

  final bool success;
  final bool definitive;
  final ProbeKind kind;
  final int? latencyMs;
  final String detail;
}

abstract class VpnCore {
  Stream<VpnCoreState> get stateStream;
  Stream<TrafficSnapshot> get trafficStream;
  VpnCoreState get state;

  Future<void> initialize();
  Future<void> connect(VpnNode node, AppSettings settings);
  Future<void> disconnect();

  /// Performs a profile reachability/latency test without requesting Android
  /// VPN permission and without starting a system VPN tunnel.
  Future<ProbeResult> test(
    VpnNode node,
    Duration timeout, {
    AppSettings settings = const AppSettings(),
  });

  /// Validates the tunnel only after the user explicitly pressed Connect.
  Future<ProbeResult> validateConnected(Duration timeout);

  Future<void> dispose();
}
