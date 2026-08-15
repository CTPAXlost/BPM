import '../models/app_settings.dart';
import '../models/vpn_node.dart';

enum VpnCoreState { disconnected, preparing, connecting, connected, disconnecting, error }

class TrafficSnapshot {
  const TrafficSnapshot({this.downloadSpeed = 0, this.uploadSpeed = 0, this.totalDownloaded = 0, this.totalUploaded = 0});
  final int downloadSpeed;
  final int uploadSpeed;
  final int totalDownloaded;
  final int totalUploaded;
}

class ProbeResult {
  const ProbeResult({required this.success, required this.definitive, this.latencyMs, this.detail = ''});
  final bool success;
  final bool definitive;
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
  Future<ProbeResult> test(VpnNode node, Duration timeout, {AppSettings settings = const AppSettings()});
  Future<ProbeResult> validateConnected(Duration timeout);
  Future<void> dispose();
}
