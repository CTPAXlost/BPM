import 'dart:async';
import 'dart:io';

import 'package:singbox_mm/singbox_mm.dart' as sb;

import '../models/app_settings.dart';
import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';
import '../utils/node_parser.dart';
import 'amneziawg_bridge.dart';
import 'vpn_core.dart';

class AndroidVpnCore implements VpnCore {
  final sb.SignboxVpn _vpn = sb.SignboxVpn();
  final AmneziaWgBridge _awg = AmneziaWgBridge();
  final StreamController<VpnCoreState> _states =
      StreamController<VpnCoreState>.broadcast();
  final StreamController<TrafficSnapshot> _traffic =
      StreamController<TrafficSnapshot>.broadcast();

  StreamSubscription<dynamic>? _stateSub;
  StreamSubscription<dynamic>? _statsSub;
  VpnCoreState _state = VpnCoreState.disconnected;
  bool _singboxReady = false;
  bool _usingAwg = false;
  Object? _singboxInitError;

  @override
  VpnCoreState get state => _state;

  @override
  Stream<VpnCoreState> get stateStream => _states.stream;

  @override
  Stream<TrafficSnapshot> get trafficStream => _traffic.stream;

  void _emit(VpnCoreState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Эта версия приложения предназначена для Android.',
      );
    }
    try {
      await _vpn.initialize(
        const sb.SingboxRuntimeOptions(
          logLevel: 'warn',
          tunInterfaceName: 'pokolenie-tun',
          statsEmitIntervalMs: 1200,
        ),
      );
      _singboxReady = true;
      _stateSub = _vpn.stateStream.listen((dynamic value) {
        if (_usingAwg) return;
        final wire = value.toString().toLowerCase();
        if (wire.contains('disconnected')) {
          _emit(VpnCoreState.disconnected);
        } else if (wire.contains('connecting')) {
          _emit(VpnCoreState.connecting);
        } else if (wire.contains('connected')) {
          _emit(VpnCoreState.connected);
        } else if (wire.contains('error')) {
          _emit(VpnCoreState.error);
        }
      });
      _statsSub = _vpn.statsStream.listen((dynamic value) {
        if (_usingAwg || _traffic.isClosed) return;
        _traffic.add(
          TrafficSnapshot(
            downloadSpeed: (value.downloadSpeed as num?)?.toInt() ?? 0,
            uploadSpeed: (value.uploadSpeed as num?)?.toInt() ?? 0,
            totalDownloaded: (value.totalDownloaded as num?)?.toInt() ?? 0,
            totalUploaded: (value.totalUploaded as num?)?.toInt() ?? 0,
          ),
        );
      });
    } catch (error) {
      _singboxInitError = error;
      _singboxReady = false;
    }
  }

  bool _usesNativeAwg(VpnNode node) => node.protocol == VpnProtocol.warp;

  Future<void> _prepareSingboxPermission() async {
    if (!_singboxReady) {
      final reason = _singboxInitError?.toString() ?? 'неизвестная ошибка';
      throw StateError('Ядро sing-box не запустилось: $reason');
    }
    final vpnGranted = await _vpn.requestVpnPermission();
    if (!vpnGranted) {
      throw StateError('Разрешение Android VPN не выдано.');
    }
    await _vpn.requestNotificationPermission();
  }

  @override
  Future<void> connect(VpnNode node, AppSettings settings) async {
    if (_state != VpnCoreState.disconnected && _state != VpnCoreState.error) {
      throw StateError('Сначала отключи текущее VPN-соединение.');
    }
    _emit(VpnCoreState.preparing);
    try {
      if (_usesNativeAwg(node)) {
        final granted = await _awg.requestPermission();
        if (!granted) {
          throw StateError('Разрешение Android VPN не выдано.');
        }
        _usingAwg = true;
        _emit(VpnCoreState.connecting);
        await _awg.start(
          config: _warpConfig(node, settings),
          name: 'pokolenie-warp',
        );
        _emit(VpnCoreState.connected);
        return;
      }

      _usingAwg = false;
      await _prepareSingboxPermission();
      final featureSettings = sb.SingboxFeatureSettings(
        advanced: const sb.AdvancedOptions(
          memoryLimit: true,
          debugMode: false,
          logLevel: 'warn',
        ),
        route: sb.RouteOptions(
          region: 'other',
          blockAdvertisements: false,
          bypassLan: settings.bypassLan,
          resolveDestination: true,
          ipv6RouteMode: sb.SingboxIpv6RouteMode.disable,
        ),
        dns: sb.DnsOptions(
          providerPreset: sb.DnsProviderPreset.custom,
          remoteDns: settings.dns,
          directDns: '1.1.1.1',
          enableDnsRouting: true,
        ),
        inbound: sb.InboundOptions(
          serviceMode: sb.SingboxServiceMode.vpn,
          strictRoute: settings.strictRoute,
          tunImplementation: sb.SingboxTunImplementation.gvisor,
          mixedPort: 2080,
          transparentProxyPort: 2081,
          shareVpnInLocalNetwork: false,
          splitTunnelingEnabled:
              settings.splitTunnelMode != SplitTunnelMode.off &&
              settings.splitTunnelPackages.isNotEmpty,
          includePackages: settings.splitTunnelMode == SplitTunnelMode.include
              ? settings.splitTunnelPackages
              : const <String>[],
          excludePackages: settings.splitTunnelMode == SplitTunnelMode.exclude
              ? settings.splitTunnelPackages
              : const <String>[],
        ),
        misc: const sb.MiscOptions(
          connectionTestUrl:
              'https://connectivitycheck.gstatic.com/generate_204',
          urlTestInterval: Duration(minutes: 10),
          clashApiPort: 16756,
        ),
      );
      final parsed = _vpn.parseConfigLink(node.rawConfig);
      await _vpn.applyProfile(
        profile: parsed.profile,
        featureSettings: featureSettings,
        throttlePolicy: sb.TrafficThrottlePolicy(
          tunMtu: settings.mtu,
          enableAutoMtuProbe: settings.adaptiveMtu,
          udpFragment: true,
        ),
      );
      _emit(VpnCoreState.connecting);
      await _vpn.start();
      _emit(VpnCoreState.connected);
    } catch (_) {
      _emit(VpnCoreState.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == VpnCoreState.disconnected) return;
    _emit(VpnCoreState.disconnecting);
    try {
      if (_usingAwg) {
        await _awg.stop();
      } else if (_singboxReady) {
        await _vpn.stop();
      }
    } finally {
      _usingAwg = false;
      if (!_traffic.isClosed) _traffic.add(const TrafficSnapshot());
      _emit(VpnCoreState.disconnected);
    }
  }

  @override
  Future<ProbeResult> test(
    VpnNode node,
    Duration timeout, {
    AppSettings settings = const AppSettings(),
  }) async {
    if (!Platform.isAndroid) {
      return const ProbeResult.failure(
        'Проверка подключения доступна только в Android-сборке.',
        definitive: false,
      );
    }
    if (_state != VpnCoreState.disconnected) {
      return const ProbeResult.failure(
        'Отключи активный VPN перед проверкой подключения.',
        definitive: false,
      );
    }
    if (node.protocol != VpnProtocol.warp && !_singboxReady) {
      final reason = _singboxInitError?.toString() ?? 'неизвестная ошибка';
      return ProbeResult.failure(
        'Ядро sing-box не инициализировано: $reason',
        definitive: false,
      );
    }
    if (node.protocol == VpnProtocol.warp) {
      final error = NodeParser.catalogCompatibilityError(node);
      if (error != null) {
        return ProbeResult.failure(
          'WARP-конфиг повреждён: $error',
          kind: ProbeKind.configValidation,
        );
      }
    }

    final started = DateTime.now();
    try {
      await connect(node, settings);
      final elapsed = DateTime.now().difference(started);
      final remaining = timeout - elapsed;
      if (remaining <= Duration.zero) {
        return const ProbeResult.failure(
          'Туннель не успел передать трафик до истечения тайм-аута.',
        );
      }
      final validation = await validateConnected(remaining);
      if (validation.success) {
        return ProbeResult.urlTestSuccess(
          validation.latencyMs ?? elapsed.inMilliseconds,
          detail: node.protocol == VpnProtocol.warp
              ? 'Подключение и HTTPS через временный WARP/AWG-туннель подтверждены.'
              : 'Подключение и HTTPS через временный VPN-туннель подтверждены.',
        );
      }
      return ProbeResult.failure(validation.detail,
          definitive: validation.definitive);
    } on TimeoutException {
      return const ProbeResult.failure(
        'Подключение и передача HTTPS-трафика не подтвердились вовремя.',
      );
    } on sb.SignboxVpnException catch (error) {
      return ProbeResult.failure('${error.code}: ${error.message}');
    } catch (error) {
      final lower = error.toString().toLowerCase();
      final parseFailure =
          lower.contains('parse') ||
          lower.contains('invalid') ||
          lower.contains('format');
      return ProbeResult.failure(
        'Проверка подключения не выполнена: $error',
        definitive: parseFailure ||
            (!lower.contains('permission') &&
                !lower.contains('разрешен') &&
                !lower.contains('разрешён')),
      );
    } finally {
      try {
        await disconnect();
      } catch (_) {
        // Best-effort cleanup after an isolated full-tunnel probe.
      }
    }
  }

  @override
  Future<ProbeResult> validateConnected(Duration timeout) async {
    if (_state != VpnCoreState.connected) {
      return const ProbeResult.failure(
        'VPN ещё не подключён.',
        kind: ProbeKind.connectedTunnel,
        definitive: false,
      );
    }
    final started = DateTime.now();
    try {
      while (DateTime.now().difference(started) < timeout) {
        final probe = await _awg.probeVpnNetwork();
        if (probe.success) {
          return ProbeResult.connectedTunnelSuccess(
            probe.latencyMs > 0
                ? probe.latencyMs
                : DateTime.now().difference(started).inMilliseconds,
            detail: _usingAwg
                ? 'HTTPS-трафик через WARP/AWG подтверждён двумя независимыми адресами.'
                : 'HTTPS-трафик через VPN подтверждён двумя независимыми адресами.',
          );
        }
        if (_usingAwg) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
          continue;
        }
        final details = await _vpn.getStateDetails();
        if (details.state == sb.VpnConnectionState.error) {
          return ProbeResult.failure(
            details.detailCode ?? 'VPN-ядро сообщило об ошибке.',
            kind: ProbeKind.connectedTunnel,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final details = await _vpn.getStateDetails();
      return ProbeResult.failure(
        details.detailCode ??
            'Туннель поднялся, но HTTPS через VPN-сеть не прошёл.',
        kind: ProbeKind.connectedTunnel,
      );
    } catch (error) {
      return ProbeResult.failure(
        'Проверка подключённого VPN не завершена: $error',
        kind: ProbeKind.connectedTunnel,
        definitive: false,
      );
    }
  }

  String _warpConfig(VpnNode node, AppSettings settings) {
    final embedded = node.metadata['wg_quick']?.toString().trim() ?? '';
    final raw = node.rawConfig.trim();
    final config = embedded.isNotEmpty
        ? embedded
        : (raw.toLowerCase().startsWith('[interface]') ? raw : '');
    if (config.isEmpty ||
        !config.toLowerCase().contains('[interface]') ||
        !config.toLowerCase().contains('[peer]')) {
      throw const FormatException(
        'У WARP-профиля отсутствует полный WireGuard/AmneziaWG конфиг.',
      );
    }

    final lines = config.replaceAll('\r\n', '\n').split('\n').where((line) {
      final key = line.trimLeft().toLowerCase();
      return !key.startsWith('mtu =') &&
          !key.startsWith('includedapplications =') &&
          !key.startsWith('excludedapplications =');
    }).toList();
    final interfaceIndex = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '[interface]',
    );
    if (interfaceIndex < 0) {
      throw const FormatException('В WARP-профиле нет секции [Interface].');
    }
    lines.insert(interfaceIndex + 1, 'MTU = ${settings.mtu}');
    if (settings.splitTunnelMode != SplitTunnelMode.off &&
        settings.splitTunnelPackages.isNotEmpty) {
      final key = settings.splitTunnelMode == SplitTunnelMode.include
          ? 'IncludedApplications'
          : 'ExcludedApplications';
      lines.insert(
        interfaceIndex + 2,
        '$key = ${settings.splitTunnelPackages.join(", ")}',
      );
    }
    return '${lines.join('\n').trim()}\n';
  }

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _statsSub?.cancel();
    try {
      await disconnect();
    } catch (_) {
      // Best-effort shutdown.
    }
    await _states.close();
    await _traffic.close();
  }
}
