import 'dart:async';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/vpn_node.dart';
import '../utils/node_parser.dart';
import 'amneziawg_bridge.dart';
import 'vpn_core.dart';

class AndroidVpnCore implements VpnCore {
  final AmneziaWgBridge _awg = AmneziaWgBridge();
  final _states = StreamController<VpnCoreState>.broadcast();
  final _traffic = StreamController<TrafficSnapshot>.broadcast();
  VpnCoreState _state = VpnCoreState.disconnected;
  bool _silentProbe = false;
  bool _probeInProgress = false;
  Timer? _statsTimer;
  bool _readingStats = false;
  int _lastRx = 0;
  int _lastTx = 0;
  DateTime? _lastSample;

  @override VpnCoreState get state => _state;
  @override Stream<VpnCoreState> get stateStream => _states.stream;
  @override Stream<TrafficSnapshot> get trafficStream => _traffic.stream;

  void _emit(VpnCoreState value) {
    _state = value;
    if (!_silentProbe && !_states.isClosed) _states.add(value);
  }

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid) throw UnsupportedError('Рабочее VPN-ядро этой сборки доступно только на Android.');
    // Deliberately does not request Android VPN permission. Permission is
    // requested only after an explicit Connect or Test action.
  }

  @override
  Future<void> connect(VpnNode node, AppSettings settings) async {
    if (_state != VpnCoreState.disconnected && _state != VpnCoreState.error) {
      throw StateError('Сначала отключи текущее WARP-соединение.');
    }
    final validation = NodeParser.validationError(node);
    if (validation != null) throw FormatException('Некорректный WARP-конфиг: $validation');
    _emit(VpnCoreState.preparing);
    try {
      if (!await _awg.requestPermission()) throw StateError('Разрешение Android VPN не выдано.');
      _emit(VpnCoreState.connecting);
      await _awg.start(config: _warpConfig(node, settings), name: 'pokolenie-warp');
      _emit(VpnCoreState.connected);
      if (!_silentProbe) _startStatistics();
    } catch (_) {
      _emit(VpnCoreState.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == VpnCoreState.disconnected) return;
    _emit(VpnCoreState.disconnecting);
    _stopStatistics();
    try { await _awg.stop(); } finally {
      if (!_traffic.isClosed) _traffic.add(const TrafficSnapshot());
      _emit(VpnCoreState.disconnected);
    }
  }

  @override
  Future<ProbeResult> test(VpnNode node, Duration timeout, {AppSettings settings = const AppSettings()}) async {
    if (_probeInProgress || _state != VpnCoreState.disconnected) {
      return const ProbeResult(success: false, definitive: false, detail: 'Другая проверка или VPN-соединение уже активно.');
    }
    final validation = NodeParser.validationError(node);
    if (validation != null) return ProbeResult(success: false, definitive: true, detail: validation);
    _probeInProgress = true;
    _silentProbe = true;
    final started = DateTime.now();
    try {
      await connect(node, settings).timeout(timeout);
      final remaining = timeout - DateTime.now().difference(started);
      if (remaining <= Duration.zero) return const ProbeResult(success: false, definitive: true, detail: 'Туннель не успел передать трафик.');
      return await validateConnected(remaining);
    } on TimeoutException {
      return const ProbeResult(success: false, definitive: true, detail: 'WARP не передал HTTPS-трафик до тайм-аута.');
    } catch (error) {
      final text = error.toString().toLowerCase();
      final permission = text.contains('permission') || text.contains('разрешен') || text.contains('разрешён');
      return ProbeResult(success: false, definitive: !permission, detail: 'Проверка не выполнена: $error');
    } finally {
      try { await disconnect(); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
      _silentProbe = false;
      _probeInProgress = false;
    }
  }

  @override
  Future<ProbeResult> validateConnected(Duration timeout) async {
    if (_state != VpnCoreState.connected) return const ProbeResult(success: false, definitive: false, detail: 'Туннель ещё не подключён.');
    final started = DateTime.now();
    String detail = '';
    while (DateTime.now().difference(started) < timeout) {
      try {
        final probe = await _awg.probeVpnNetwork();
        detail = probe.detail;
        if (probe.success) {
          return ProbeResult(success: true, definitive: true, latencyMs: probe.latencyMs > 0 ? probe.latencyMs : DateTime.now().difference(started).inMilliseconds, detail: 'HTTPS через WARP подтверждён.');
        }
      } catch (error) { detail = error.toString(); }
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    return ProbeResult(success: false, definitive: true, detail: detail.isEmpty ? 'Туннель поднялся, но HTTPS через него не прошёл.' : detail);
  }

  void _startStatistics() {
    _stopStatistics();
    _lastSample = DateTime.now();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_state != VpnCoreState.connected || _readingStats) return;
      _readingStats = true;
      try {
        final stats = await _awg.statistics();
        final now = DateTime.now();
        final elapsed = now.difference(_lastSample ?? now).inMilliseconds;
        final rxDelta = (stats.received - _lastRx).clamp(0, 1 << 62);
        final txDelta = (stats.sent - _lastTx).clamp(0, 1 << 62);
        _lastRx = stats.received; _lastTx = stats.sent; _lastSample = now;
        if (!_traffic.isClosed) _traffic.add(TrafficSnapshot(
          downloadSpeed: elapsed <= 0 ? 0 : rxDelta * 1000 ~/ elapsed,
          uploadSpeed: elapsed <= 0 ? 0 : txDelta * 1000 ~/ elapsed,
          totalDownloaded: stats.received, totalUploaded: stats.sent,
        ));
      } catch (_) {} finally { _readingStats = false; }
    });
  }

  void _stopStatistics() {
    _statsTimer?.cancel(); _statsTimer = null; _readingStats = false;
    _lastRx = 0; _lastTx = 0; _lastSample = null;
  }

  String _warpConfig(VpnNode node, AppSettings settings) {
    final config = NodeParser.extractSingleWgQuick(node.metadata['wg_quick']?.toString() ?? node.rawConfig)!;
    final lines = config.split('\n').where((line) {
      final key = line.trimLeft().toLowerCase();
      return !key.startsWith('mtu =') && !key.startsWith('dns =') && !key.startsWith('includedapplications =') && !key.startsWith('excludedapplications =');
    }).toList();
    final index = lines.indexWhere((line) => line.trim().toLowerCase() == '[interface]');
    lines.insert(index + 1, 'MTU = ${settings.mtu}');
    lines.insert(index + 2, 'DNS = ${settings.dns}');
    if (settings.splitTunnelMode != SplitTunnelMode.off && settings.splitTunnelPackages.isNotEmpty) {
      final key = settings.splitTunnelMode == SplitTunnelMode.include ? 'IncludedApplications' : 'ExcludedApplications';
      lines.insert(index + 3, '$key = ${settings.splitTunnelPackages.join(', ')}');
    }
    return '${lines.join('\n').trim()}\n';
  }

  @override
  Future<void> dispose() async {
    _stopStatistics();
    try { await disconnect(); } catch (_) {}
    await _states.close(); await _traffic.close();
  }
}
