import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/vpn_node.dart';
import '../utils/node_parser.dart';
import 'vpn_core.dart';

/// Produces one Windows command-line string for `ProcessStartInfo.Arguments`.
/// Backslashes before a quote (and at the end) must be doubled according to
/// the CommandLineToArgvW convention. Passing a PowerShell String[] is not
/// sufficient because Start-Process joins it and loses quotes around paths.
String buildWindowsArgumentLine(List<String> arguments) {
  String quoteArgument(String argument) {
    final result = StringBuffer('"');
    var backslashes = 0;
    for (final codeUnit in argument.codeUnits) {
      if (codeUnit == 0x5c) {
        backslashes++;
        continue;
      }
      if (codeUnit == 0x22) {
        result.write('\\' * (backslashes * 2 + 1));
        result.write('"');
      } else {
        result.write('\\' * backslashes);
        result.writeCharCode(codeUnit);
      }
      backslashes = 0;
    }
    result.write('\\' * (backslashes * 2));
    result.write('"');
    return result.toString();
  }

  return arguments.map(quoteArgument).join(' ');
}

({int received, int sent})? parseAwgDumpCounters(String output) {
  final lines = output
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  var received = 0;
  var sent = 0;
  var peers = 0;
  for (final line in lines.skip(1)) {
    final fields = line.split(RegExp(r'\s+'));
    if (fields.length < 8) continue;
    final peerReceived = int.tryParse(fields[5]);
    final peerSent = int.tryParse(fields[6]);
    if (peerReceived == null || peerSent == null) continue;
    received += peerReceived;
    sent += peerSent;
    peers++;
  }
  return peers == 0 ? null : (received: received, sent: sent);
}

({int received, int sent})? parseWindowsAdapterCounters(String output) {
  final match = RegExp(r'(?m)^\s*(\d+)\s+(\d+)\s*$').firstMatch(output);
  if (match == null) return null;
  final received = int.tryParse(match.group(1)!);
  final sent = int.tryParse(match.group(2)!);
  return received == null || sent == null ? null : (received: received, sent: sent);
}

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
    await _discoverRuntime();
    _runtimeConfig = File('${await _runtimeDirectoryPath(createAndProtect: false)}\\$_tunnelName.conf');
    if (_amneziaExe != null && await _serviceRunning()) {
      _serviceInstalled = true;
      _emit(VpnCoreState.connected);
      _startStatistics();
    }
  }

  Future<void> _discoverRuntime() async {
    final env = Platform.environment;
    final applicationDirectory = File(Platform.resolvedExecutable).parent.path;
    final roots = <String>{
      if ((env['ProgramFiles'] ?? '').isNotEmpty) env['ProgramFiles']!,
      if ((env['ProgramFiles(x86)'] ?? '').isNotEmpty) env['ProgramFiles(x86)']!,
    };
    final amneziaCandidates = <String>[
      if (_isInstalledApplicationDirectory(applicationDirectory, env))
        '$applicationDirectory\\runtime\\amneziawg\\amneziawg.exe',
      for (final root in roots) '$root\\AmneziaWG\\amneziawg.exe',
      for (final root in roots) '$root\\Programs\\AmneziaWG\\amneziawg.exe',
    ];
    _amneziaExe = null;
    _awgExe = null;
    for (final candidate in amneziaCandidates) {
      if (await File(candidate).exists()) { _amneziaExe = candidate; break; }
    }
    if (_amneziaExe != null) {
      final sibling = '${File(_amneziaExe!).parent.path}\\awg.exe';
      if (await File(sibling).exists()) _awgExe = sibling;
    }
  }

  bool _isInstalledApplicationDirectory(String directory, Map<String, String> env) {
    final normalized = Directory(directory).absolute.path.toLowerCase();
    final protectedRoots = <String>[
      env['ProgramFiles'] ?? '',
      env['ProgramFiles(x86)'] ?? '',
    ].where((root) => root.isNotEmpty).map((root) => Directory(root).absolute.path.toLowerCase());
    return protectedRoots.any((root) => normalized == root || normalized.startsWith('$root\\'));
  }

  String get _runtimeMissing =>
      'Windows-ядро доступно только после установки Pokolenie WARP через Setup.exe. Portable-запуск из Загрузок или Рабочего стола запрещён: системная служба требует защищённый путь Program Files.';

  Future<String> _currentUserSid() async {
    final result = await Process.run(
      'whoami.exe',
      const <String>['/user', '/fo', 'csv', '/nh'],
      runInShell: false,
    );
    final match = RegExp(r'S-\d-(?:\d+-)+\d+', caseSensitive: false)
        .firstMatch('${result.stdout}\n${result.stderr}');
    if (result.exitCode != 0 || match == null) {
      throw StateError('Не удалось определить SID текущего пользователя Windows.');
    }
    return match.group(0)!.toUpperCase();
  }

  /// Keeps the service configuration (and its private key) out of user-name
  /// paths. Old AmneziaWG releases cannot reliably decode a service command
  /// line containing Cyrillic, while a SID is always ASCII. The directory ACL
  /// also prevents other local users from reading the private key.
  Future<String> _runtimeDirectoryPath({required bool createAndProtect}) async {
    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.isEmpty) {
      throw StateError('Windows не сообщил путь ProgramData.');
    }
    final sid = await _currentUserSid();
    final directory = Directory('$programData\\PokolenieWARP\\$sid\\runtime');
    if (createAndProtect) {
      await directory.create(recursive: true);
      final acl = await Process.run(
        'icacls.exe',
        <String>[
          directory.path,
          '/inheritance:r',
          '/grant:r',
          '*${sid}:(OI)(CI)F',
          '*S-1-5-18:(OI)(CI)F',
        ],
        runInShell: false,
      );
      if (acl.exitCode != 0) {
        throw StateError('Не удалось защитить каталог конфигурации WARP: ${acl.stderr}');
      }
    }
    return directory.path;
  }

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
      final directory = Directory(await _runtimeDirectoryPath(createAndProtect: true));
      _runtimeConfig = File('${directory.path}\\$_tunnelName.conf');
      await _runtimeConfig!.writeAsString(_windowsConfig(node, settings), flush: true);
      _emit(VpnCoreState.connecting);
      final exitCode = await _runElevated(<String>['/installtunnelservice', _runtimeConfig!.path]);
      if (exitCode != 0) throw StateError('AmneziaWG service installer: код $exitCode.');
      _serviceInstalled = true;
      // The first Wintun adapter installation on a fresh Windows system can
      // remain START_PENDING well beyond 15 seconds. Do not tear the service
      // down while Windows is still installing and binding the signed driver.
      final running = await _waitForService(running: true, timeout: const Duration(seconds: 60));
      if (!running) {
        throw StateError(
          'Служба AmneziaWG не перешла в состояние RUNNING. ${await _serviceDiagnostics()}',
        );
      }
      _emit(VpnCoreState.connected);
      if (!_silentProbe) _startStatistics();
    } catch (_) {
      // A successful installer exit does not guarantee that the service could
      // parse the profile and start. Never leave a failed LocalSystem service
      // or its private-key file behind after a connection attempt.
      var serviceRemoved = !_serviceInstalled;
      if (_serviceInstalled && _amneziaExe != null) {
        try {
          final uninstallCode = await _runElevated(<String>['/uninstalltunnelservice', _tunnelName]);
          serviceRemoved = uninstallCode == 0 &&
              await _waitForServiceRemoved(const Duration(seconds: 8));
        } catch (_) {}
      }
      if (serviceRemoved) {
        try {
          if (_runtimeConfig != null && await _runtimeConfig!.exists()) {
            await _runtimeConfig!.delete();
          }
        } catch (_) {}
        _runtimeConfig = null;
        _serviceInstalled = false;
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
    var serviceRemoved = !_serviceInstalled;
    try {
      if (_amneziaExe != null && _serviceInstalled) {
        final exitCode = await _runElevated(<String>['/uninstalltunnelservice', _tunnelName]);
        if (exitCode != 0) {
          throw StateError('Отключение AmneziaWG отменено или завершилось с кодом $exitCode.');
        }
        serviceRemoved = await _waitForServiceRemoved(const Duration(seconds: 12));
        if (!serviceRemoved) throw StateError('Служба AmneziaWG не была удалена.');
      }
      if (serviceRemoved) {
        try { if (_runtimeConfig != null && await _runtimeConfig!.exists()) await _runtimeConfig!.delete(); } catch (_) {}
        _runtimeConfig = null;
        _serviceInstalled = false;
      }
      if (!_traffic.isClosed) _traffic.add(const TrafficSnapshot());
      _emit(VpnCoreState.disconnected);
    } catch (_) {
      _emit(VpnCoreState.error);
      rethrow;
    }
  }

  Future<int> _runElevated(List<String> arguments) async {
    final executable = _amneziaExe;
    if (executable == null) throw StateError(_runtimeMissing);
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final argumentLine = buildWindowsArgumentLine(arguments);
    final script = r'$p=Start-Process -FilePath ' + quote(executable) +
        ' -ArgumentList ${quote(argumentLine)} -Verb RunAs -WindowStyle Hidden -Wait -PassThru' +
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

  Future<bool> _serviceExists() async {
    final result = await Process.run('sc.exe', <String>['query', _serviceName], runInShell: false);
    return result.exitCode == 0;
  }

  Future<bool> _waitForServiceRemoved(Duration timeout) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      if (!await _serviceExists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return !await _serviceExists();
  }

  Future<String> _serviceDiagnostics() async {
    try {
      final result = await Process.run(
        'sc.exe',
        <String>['queryex', _serviceName],
        runInShell: false,
      );
      final output = '${result.stdout}\n${result.stderr}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return output.isEmpty ? 'Служба не зарегистрирована.' : output;
    } catch (error) {
      return 'Диагностика службы недоступна: $error';
    }
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
    const targets = <String>[
      'https://1.1.1.1/cdn-cgi/trace',
      'https://www.cloudflare.com/cdn-cgi/trace',
      'https://connectivitycheck.gstatic.com/generate_204',
    ];
    var targetIndex = 0;
    while (DateTime.now().difference(started) < timeout) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4)..findProxy = (_) => 'DIRECT';
      try {
        final target = targets[targetIndex++ % targets.length];
        final request = await client.getUrl(Uri.parse(target));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close().timeout(const Duration(seconds: 5));
        final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 5));
        final traceConfirmsWarp = target.contains('cdn-cgi/trace') &&
            (body.contains('warp=on') || body.contains('warp=plus'));
        final connectivityCheckPassed = target.contains('generate_204') &&
            (response.statusCode == 204 || response.statusCode == 200);
        if (traceConfirmsWarp || connectivityCheckPassed) {
          return ProbeResult(success: true, definitive: true, latencyMs: DateTime.now().difference(started).inMilliseconds, detail: 'HTTPS через Windows WARP подтверждён.');
        }
        lastError = traceConfirmsWarp
            ? null
            : '$target: HTTP ${response.statusCode}, WARP не подтверждён';
      } catch (error) { lastError = error; } finally { client.close(force: true); }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return ProbeResult(success: false, definitive: true, detail: 'Контрольный HTTPS через Windows WARP не прошёл: ${lastError ?? 'тайм-аут'}.');
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
      if (!await _serviceRunning()) {
        _stopStatistics();
        if (!_traffic.isClosed) _traffic.add(const TrafficSnapshot());
        _emit(VpnCoreState.error);
        return;
      }
      ({int received, int sent})? counters;
      try {
        counters = await _readTrafficCounters().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Statistics are optional and must never destabilise the VPN session.
        return;
      }
      if (counters == null) return;
      final rx = counters.received;
      final tx = counters.sent;
      final now = DateTime.now(); final elapsed = now.difference(_lastSample ?? now).inMilliseconds;
      if (!_traffic.isClosed) _traffic.add(TrafficSnapshot(
        downloadSpeed: elapsed <= 0 ? 0 : (rx - _lastRx).clamp(0, 1 << 62) * 1000 ~/ elapsed,
        uploadSpeed: elapsed <= 0 ? 0 : (tx - _lastTx).clamp(0, 1 << 62) * 1000 ~/ elapsed,
        totalDownloaded: rx, totalUploaded: tx,
      ));
      _lastRx = rx; _lastTx = tx; _lastSample = now;
    } finally { _readingStats = false; }
  }

  Future<({int received, int sent})?> _readTrafficCounters() async {
    // The network adapter is the authoritative Windows traffic source. It is
    // also readable when the tunnel service's userspace pipe is unavailable
    // to the desktop user. Telemetry is observational and must never affect a
    // healthy tunnel.
    const script = r'''
$adapter = Get-NetAdapter -IncludeHidden -Name 'pokolenie-warp' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $adapter) {
  $adapter = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'AmneziaWG|WireGuard|Wintun' } |
    Select-Object -First 1
}
if ($null -ne $adapter) {
  $stats = $adapter | Get-NetAdapterStatistics -ErrorAction SilentlyContinue
  if ($null -ne $stats) { Write-Output "$($stats.ReceivedBytes) $($stats.SentBytes)" }
}
''';
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    final encoded = base64Encode(bytes);
    final adapterResult = await Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
      runInShell: false,
    );
    if (adapterResult.exitCode == 0) {
      final adapterCounters = parseWindowsAdapterCounters(adapterResult.stdout.toString());
      if (adapterCounters != null) return adapterCounters;
    }

    final awgResult = await Process.run(_awgExe!, <String>['show', _tunnelName, 'dump'], runInShell: false);
    if (awgResult.exitCode != 0) return null;
    return parseAwgDumpCounters(awgResult.stdout.toString());
  }

  void _stopStatistics() { _statsTimer?.cancel(); _statsTimer = null; _readingStats = false; _lastRx = 0; _lastTx = 0; _lastSample = null; }

  @override
  Future<void> dispose() async {
    _stopStatistics();
    try { await disconnect(); } catch (_) {}
    await _states.close(); await _traffic.close();
  }
}
