import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/vpn_node.dart';
import '../utils/node_parser.dart';
import 'vpn_core.dart';

/// Windows host for the official AmneziaWG tunnel service. It deliberately
/// refuses to fake Android package split tunnelling: Windows app filtering
/// requires a separately audited WFP driver.
class WindowsVpnCore implements VpnCore {
  static const _tunnelName = 'pokolenie-warp';
  static const _serviceName = r'AmneziaWGTunnel$pokolenie-warp';
  final _states = StreamController<VpnCoreState>.broadcast();
  final _traffic = StreamController<TrafficSnapshot>.broadcast();
  VpnCoreState _state = VpnCoreState.disconnected;
  String? _amneziaExe;
  String? _awgExe;
  File? _runtimeConfig;
  Timer? _statsTimer;
  bool _readingStats = false;
  bool _probeInProgress = false;
  bool _silentProbe = false;
  bool _serviceInstalled = false;
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
    if (!Platform.isWindows) throw UnsupportedError('Windows VPN core запущен не на Windows.');
    final env = Platform.environment;
    final roots = <String>{
      if ((env['ProgramFiles'] ?? '').isNotEmpty) env['ProgramFiles']!,
      if ((env['ProgramFiles(x86)'] ?? '').isNotEmpty) env['ProgramFiles(x86)']!,
      if ((env['LOCALAPPDATA'] ?? '').isNotEmpty) env['LOCALAPPDATA']!,
    };
    final amneziaCandidates = <String>[
      for (final root in roots) '$root\\AmneziaWG\\amneziawg.exe',
      for (final root in roots) '$root\\Programs\\AmneziaWG\\amneziawg.exe',
    ];
    for (final candidate in amneziaCandidates) {
      if (await File(candidate).exists()) { _amneziaExe = candidate; break; }
    }
    if (_amneziaExe != null) {
      final sibling = '${File(_amneziaExe!).parent.path}\\awg.exe';
      if (await File(sibling).exists()) _awgExe = sibling;
    }
    final local = env['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      _runtimeConfig = File('$local\\Pokolenie WARP\\runtime\\$_tunnelName.conf');
    }
    if (_amneziaExe != null && await _serviceRunning()) {
      _serviceInstalled = true;
      _emit(VpnCoreState.connected);
      _startStatistics();
    }
  }

  String get _runtimeMissing =>
      'Установи официальный AmneziaWG for Windows, затем перезапусти Pokolenie WARP.';

  @override
  Future<void> connect(VpnNode node, AppSettings settings) async {
    if (_state != VpnCoreState.disconnected && _state != VpnCoreState.error) {
      throw StateError('Сначала отключи текущий туннель.');
    }
    if (_amneziaExe == null) throw StateError(_runtimeMissing);
    if (settings.splitTunnelMode != SplitTunnelMode.off && settings.splitTunnelPackages.isNotEmpty) {
      throw UnsupportedError('Разделение по Android package ID неприменимо в Windows. Выключи его для подключения.');
    }
    final error = NodeParser.validationError(node);
    if (error != null) throw FormatException('Некорректный WARP-конфиг: $error');
    _emit(VpnCoreState.preparing);
    try {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || local.isEmpty) throw StateError('Windows не сообщил LOCALAPPDATA.');
      final directory = Directory('$local\\Pokolenie WARP\\runtime');
      await directory.create(recursive: true);
      _runtimeConfig = File('${directory.path}\\$_tunnelName.conf');
      await _runtimeConfig!.writeAsString(_windowsConfig(node, settings), flush: true);
      _emit(VpnCoreState.connecting);
      final exitCode = await _runElevated(<String>['/installtunnelservice', _runtimeConfig!.path]);
      if (exitCode != 0) throw StateError('AmneziaWG service installer: код $exitCode.');
      _serviceInstalled = true;
      final running = await _waitForService(running: true, timeout: const Duration(seconds: 15));
      if (!running) throw StateError('Служба AmneziaWG не перешла в состояние RUNNING.');
      _emit(VpnCoreState.connected);
      if (!_silentProbe) _startStatistics();
    } catch (_) {
      if (!_serviceInstalled) {
        try {
          if (_runtimeConfig != null && await _runtimeConfig!.exists()) {
            await _runtimeConfig!.delete();
          }
        } catch (_) {}
        _runtimeConfig = null;
      }
      _emit(VpnCoreState.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == VpnCoreState.disconnected) return;
    _emit(VpnCoreState.disconnecting);
    _stopStatistics();
    try {
      if (_amneziaExe != null && _serviceInstalled) {
        await _runElevated(<String>['/uninstalltunnelservice', _tunnelName]);
      }
      await _waitForService(running: false, timeout: const Duration(seconds: 12));
    } finally {
      try { if (_runtimeConfig != null && await _runtimeConfig!.exists()) await _runtimeConfig!.delete(); } catch (_) {}
      _runtimeConfig = null;
      _serviceInstalled = false;
      if (!_traffic.isClosed) _traffic.add(const TrafficSnapshot());
      _emit(VpnCoreState.disconnected);
    }
  }

  Future<int> _runElevated(List<String> arguments) async {
    final executable = _amneziaExe;
    if (executable == null) throw StateError(_runtimeMissing);
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final argumentList = arguments.map(quote).join(',');
    final script = r'$p=Start-Process -FilePath ' + quote(executable) +
        ' -ArgumentList @($argumentList) -Verb RunAs -WindowStyle Hidden -Wait -PassThru' +
        r'; exit $p.ExitCode';
    final bytes = <int>[];
    for (final unit in script.codeUnits) { bytes..add(unit & 0xff)..add(unit >> 8); }
    final result = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-EncodedCommand', base64Encode(bytes)],
      runInShell: false,
    );
    return result.exitCode;
  }

  Future<bool> _serviceRunning() async {
    final result = await Process.run('sc.exe', <String>['query', _serviceName], runInShell: false);
    final output = '${result.stdout}\n${result.stderr}'.toUpperCase();
    return result.exitCode == 0 && output.contains('RUNNING');
  }

  Future<bool> _waitForService({required bool running, required Duration timeout}) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      if (await _serviceRunning() == running) return true;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return await _serviceRunning() == running;
  }

  @override
  Future<ProbeResult> validateConnected(Duration timeout) async {
    if (_state != VpnCoreState.connected) return const ProbeResult(success: false, definitive: false, detail: 'Туннель ещё не подключён.');
    final started = DateTime.now();
    Object? lastError;
    while (DateTime.now().difference(started) < timeout) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4)..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(Uri.parse('https://connectivitycheck.gstatic.com/generate_204'));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close().timeout(const Duration(seconds: 5));
        await response.drain<void>();
        if (response.statusCode == 204 || response.statusCode == 200) {
          return ProbeResult(success: true, definitive: true, latencyMs: DateTime.now().difference(started).inMilliseconds, detail: 'HTTPS через Windows WARP подтверждён.');
        }
        lastError = 'HTTP ${response.statusCode}';
      } catch (error) { lastError = error; } finally { client.close(force: true); }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return ProbeResult(success: false, definitive: true, detail: 'HTTPS через Windows WARP не прошёл: ${lastError ?? 'тайм-аут'}.');
  }

  @override
  Future<ProbeResult> test(VpnNode node, Duration timeout, {AppSettings settings = const AppSettings()}) async {
    if (_probeInProgress || _state != VpnCoreState.disconnected) return const ProbeResult(success: false, definitive: false, detail: 'Другая проверка уже выполняется.');
    _probeInProgress = true; _silentProbe = true;
    final started = DateTime.now();
    try {
      await connect(node, settings).timeout(timeout);
      final remaining = timeout - DateTime.now().difference(started);
      if (remaining <= Duration.zero) return const ProbeResult(success: false, definitive: true, detail: 'Туннель не успел передать трафик.');
      return await validateConnected(remaining);
    } on TimeoutException {
      return const ProbeResult(success: false, definitive: true, detail: 'Windows WARP не ответил до тайм-аута.');
    } catch (error) {
      final cancelled = error.toString().contains('1223');
      return ProbeResult(success: false, definitive: !cancelled, detail: 'Проверка Windows не выполнена: $error');
    } finally {
      try { await disconnect(); } catch (_) {}
      _silentProbe = false; _probeInProgress = false;
    }
  }

  String _windowsConfig(VpnNode node, AppSettings settings) {
    final config = NodeParser.extractSingleWgQuick(node.metadata['wg_quick']?.toString() ?? node.rawConfig)!;
    final lines = config.split('\n').where((line) {
      final key = line.trimLeft().toLowerCase();
      return !key.startsWith('mtu =') && !key.startsWith('dns =') && !key.startsWith('includedapplications =') && !key.startsWith('excludedapplications =');
    }).toList();
    final index = lines.indexWhere((line) => line.trim().toLowerCase() == '[interface]');
    lines.insert(index + 1, 'MTU = ${settings.mtu}');
    lines.insert(index + 2, 'DNS = ${settings.dns}');
    return '${lines.join('\n').trim()}\n';
  }

  void _startStatistics() {
    _stopStatistics(); _lastSample = DateTime.now();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStatistics());
  }

  Future<void> _pollStatistics() async {
    if (_readingStats || _state != VpnCoreState.connected || _awgExe == null) return;
    _readingStats = true;
    try {
      final result = await Process.run(_awgExe!, <String>['show', _tunnelName, 'dump'], runInShell: false);
      if (result.exitCode != 0) return;
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return;
      var rx = 0; var tx = 0;
      for (final line in lines.skip(1)) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length >= 8) { rx += int.tryParse(fields[5]) ?? 0; tx += int.tryParse(fields[6]) ?? 0; }
      }
      final now = DateTime.now(); final elapsed = now.difference(_lastSample ?? now).inMilliseconds;
      if (!_traffic.isClosed) _traffic.add(TrafficSnapshot(
        downloadSpeed: elapsed <= 0 ? 0 : (rx - _lastRx).clamp(0, 1 << 62) * 1000 ~/ elapsed,
        uploadSpeed: elapsed <= 0 ? 0 : (tx - _lastTx).clamp(0, 1 << 62) * 1000 ~/ elapsed,
        totalDownloaded: rx, totalUploaded: tx,
      ));
      _lastRx = rx; _lastTx = tx; _lastSample = now;
    } finally { _readingStats = false; }
  }

  void _stopStatistics() { _statsTimer?.cancel(); _statsTimer = null; _readingStats = false; _lastRx = 0; _lastTx = 0; _lastSample = null; }

  @override
  Future<void> dispose() async {
    _stopStatistics();
    try { await disconnect(); } catch (_) {}
    await _states.close(); await _traffic.close();
  }
}
