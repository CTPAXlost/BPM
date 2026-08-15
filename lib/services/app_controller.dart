import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../core/core_factory.dart';
import '../core/vpn_core.dart';
import '../models/app_settings.dart';
import '../models/vpn_node.dart';
import '../utils/node_parser.dart';
import 'storage_service.dart';
import 'warp_generator_service.dart';

class AppController extends ChangeNotifier {
  final VpnCore _core = createVpnCore();
  final StorageService _storage = StorageService();
  final WarpGeneratorService _generator = WarpGeneratorService();
  final AudioPlayer _toastyPlayer = AudioPlayer();

  AppSettings _settings = const AppSettings();
  List<VpnNode> _nodes = <VpnNode>[];
  String? _selectedNodeId;
  VpnCoreState _coreState = VpnCoreState.disconnected;
  TrafficSnapshot _traffic = const TrafficSnapshot();
  DateTime? _lastWarpGeneration;
  StreamSubscription<VpnCoreState>? _stateSub;
  StreamSubscription<TrafficSnapshot>? _trafficSub;
  Timer? _toastyTimer;
  bool _loading = true;
  bool _testingAll = false;
  bool _probeInProgress = false;
  bool _importingWarp = false;
  bool _generatingWarp = false;
  bool _showToasty = false;
  int _testingCompleted = 0;
  int _testingTotal = 0;
  String? _message;

  AppSettings get settings => _settings;
  List<VpnNode> get warpNodes => List.unmodifiable(_nodes);
  String? get selectedNodeId => _selectedNodeId;
  VpnNode? get selectedNode {
    for (final node in _nodes) if (node.id == _selectedNodeId) return node;
    return _nodes.isEmpty ? null : _nodes.first;
  }
  VpnCoreState get coreState => _coreState;
  TrafficSnapshot get traffic => _traffic;
  bool get loading => _loading;
  bool get connected => _coreState == VpnCoreState.connected;
  bool get busy => _coreState == VpnCoreState.preparing || _coreState == VpnCoreState.connecting || _coreState == VpnCoreState.disconnecting;
  bool get testingAll => _testingAll;
  bool get probeInProgress => _probeInProgress;
  bool get importingWarp => _importingWarp;
  bool get generatingWarp => _generatingWarp;
  bool get showToasty => _showToasty;
  int get testingCompleted => _testingCompleted;
  int get testingTotal => _testingTotal;
  String? get message => _message;
  Duration get warpGenerationRemaining {
    if (_lastWarpGeneration == null) return Duration.zero;
    final remaining = const Duration(hours: 1) - DateTime.now().difference(_lastWarpGeneration!);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> initialize() async {
    try {
      _settings = await _storage.loadSettings();
      _lastWarpGeneration = await _storage.loadLastWarpGeneration();
      final saved = await _storage.loadNodes();
      _nodes = saved.where((node) => NodeParser.isCompatible(node)).toList();
      _selectedNodeId = await _storage.loadSelectedNodeId();
      if (!_nodes.any((node) => node.id == _selectedNodeId)) _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
      await _storage.saveNodes(_nodes); // Migrates old VLESS/other records out.
      await _storage.saveSelectedNodeId(_selectedNodeId);
      _stateSub = _core.stateStream.listen((value) { _coreState = value; notifyListeners(); });
      _trafficSub = _core.trafficStream.listen((value) { _traffic = value; notifyListeners(); });
      await _core.initialize();
    } catch (error) {
      _message = 'Не удалось запустить VPN-ядро: $error';
    } finally {
      _loading = false;
      notifyListeners();
    }
    if (_nodes.isEmpty && _settings.autoGenerateWarp) unawaited(generateOneWarp(automatic: true));
  }

  void onAppResumed() => notifyListeners();

  Future<void> updateSettings(AppSettings value) async {
    _settings = value;
    await _storage.saveSettings(value);
    notifyListeners();
  }

  Future<void> selectNode(VpnNode node) async {
    _selectedNodeId = node.id;
    await _storage.saveSelectedNodeId(node.id);
    notifyListeners();
  }

  Future<void> toggleFavorite(VpnNode node) async {
    _replace(node.copyWith(isFavorite: !node.isFavorite));
    await _persistNodes();
  }

  Future<void> connectOrDisconnect() async {
    if (connected || _coreState == VpnCoreState.error) {
      try { await _core.disconnect(); } catch (error) { _setMessage('Не удалось отключить WARP: $error'); }
      return;
    }
    var node = selectedNode;
    if (node == null) {
      await generateOneWarp(automatic: true);
      node = selectedNode;
    }
    if (node != null) await connectNode(node);
  }

  Future<void> connectNode(VpnNode node) async {
    if (_testingAll || _probeInProgress || busy) return;
    if (connected) await _core.disconnect();
    await selectNode(node);
    try {
      await _core.connect(node, _settings);
      await _playToasty();
      unawaited(_validateActive(node));
    } catch (error) {
      _setMessage('WARP не подключён: $error');
    }
  }

  Future<void> _validateActive(VpnNode node) async {
    final result = await _core.validateConnected(Duration(milliseconds: _settings.testTimeoutMs));
    if (result.success) {
      _replace(node.copyWith(health: NodeHealth.online, latencyMs: result.latencyMs, lastChecked: DateTime.now()));
      await _persistNodes();
      return;
    }
    _setMessage(result.detail);
    try { await _core.disconnect(); } catch (_) {}
    if (result.definitive && _settings.autoRemoveUnavailable) await removeNode(node, announce: true);
  }

  Future<void> testNode(VpnNode node) async {
    if (_testingAll || _probeInProgress || connected || busy) return;
    _probeInProgress = true;
    _replace(node.copyWith(health: NodeHealth.checking, clearLatency: true));
    notifyListeners();
    final result = await _core.test(node, Duration(milliseconds: _settings.testTimeoutMs), settings: _settings);
    _probeInProgress = false;
    await _applyProbe(node, result);
  }

  Future<void> testAllWarpNodes() async {
    if (_testingAll || _probeInProgress || connected || busy || _nodes.isEmpty) return;
    _testingAll = true;
    final snapshot = List<VpnNode>.from(_nodes);
    _testingTotal = snapshot.length;
    _testingCompleted = 0;
    notifyListeners();
    for (final node in snapshot) {
      if (!_nodes.any((item) => item.id == node.id)) continue;
      _replace(node.copyWith(health: NodeHealth.checking, clearLatency: true));
      notifyListeners();
      final result = await _core.test(node, Duration(milliseconds: _settings.testTimeoutMs), settings: _settings);
      await _applyProbe(node, result, announce: false);
      _testingCompleted++;
      notifyListeners();
      if (!result.definitive && !result.success) {
        _setMessage('${result.detail} Массовая проверка остановлена.');
        break;
      }
    }
    _testingAll = false;
    notifyListeners();
    if (_testingCompleted == _testingTotal) {
      _setMessage('Проверено: $_testingCompleted из $_testingTotal. Нерабочие WARP удалены.');
    }
  }

  Future<void> _applyProbe(VpnNode original, ProbeResult result, {bool announce = true}) async {
    final current = _byId(original.id);
    if (current == null) return;
    if (result.success) {
      _replace(current.copyWith(health: NodeHealth.online, latencyMs: result.latencyMs, lastChecked: DateTime.now()));
      await _persistNodes();
      if (announce) _setMessage('WARP работает: HTTPS ${result.latencyMs ?? 0} мс.');
    } else if (result.definitive && _settings.autoRemoveUnavailable) {
      await removeNode(current, announce: announce);
    } else {
      _replace(current.copyWith(health: result.definitive ? NodeHealth.offline : NodeHealth.unknown, clearLatency: true, lastChecked: DateTime.now()));
      await _persistNodes();
      if (announce) _setMessage(result.detail);
    }
  }

  Future<void> generateOneWarp({bool automatic = false}) async {
    if (_generatingWarp || _importingWarp || _testingAll || _probeInProgress) return;
    final remaining = warpGenerationRemaining;
    if (remaining > Duration.zero) {
      if (!automatic || _nodes.isEmpty) _setMessage('Новый WARP можно создать через ${remaining.inMinutes + 1} мин.');
      return;
    }
    _generatingWarp = true;
    if (automatic) _message = 'Создаю WARP-профиль прямо в приложении…';
    notifyListeners();
    try {
      final raw = await _generator.generateOne();
      final node = NodeParser.parse(raw, source: 'Автогенератор');
      if (node == null) throw const FormatException('генератор вернул неизвестный формат');
      final validation = NodeParser.validationError(node);
      if (validation != null) throw FormatException(validation);
      final generated = node.copyWith(
        name: 'WARP ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        metadata: <String, dynamic>{...node.metadata, 'auto_generated': true},
      );
      _nodes.removeWhere((item) => item.metadata['auto_generated'] == true);
      _nodes.insert(0, generated);
      _selectedNodeId = generated.id;
      _lastWarpGeneration = DateTime.now();
      await _storage.saveLastWarpGeneration(_lastWarpGeneration!);
      await _persistNodes();
      await _storage.saveSelectedNodeId(generated.id);
      _setMessage('Новый WARP создан и уже добавлен в приложение.');
    } catch (error) {
      _setMessage('Автогенерация WARP временно недоступна: $error');
    } finally {
      _generatingWarp = false;
      notifyListeners();
    }
  }

  Future<void> importWarpFile() async {
    if (_importingWarp || _generatingWarp || _testingAll || _probeInProgress) return;
    _importingWarp = true; notifyListeners();
    try {
      const group = XTypeGroup(label: 'WARP config', extensions: <String>['conf', 'txt']);
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;
      final node = NodeParser.parse(await file.readAsString(), source: 'Импорт');
      if (node == null) throw const FormatException('файл не является WireGuard/AmneziaWG конфигом');
      final validation = NodeParser.validationError(node);
      if (validation != null) throw FormatException(validation);
      _nodes.removeWhere((item) => item.id == node.id);
      _nodes.insert(0, node);
      _selectedNodeId = node.id;
      await _persistNodes(); await _storage.saveSelectedNodeId(node.id);
      _setMessage('WARP-файл добавлен и выбран.');
    } catch (error) { _setMessage('Не удалось импортировать WARP: $error'); }
    finally { _importingWarp = false; notifyListeners(); }
  }

  Future<void> removeNode(VpnNode node, {bool announce = false}) async {
    _nodes.removeWhere((item) => item.id == node.id);
    if (_selectedNodeId == node.id) _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
    await _persistNodes(); await _storage.saveSelectedNodeId(_selectedNodeId);
    if (announce) _setMessage('Нерабочий WARP удалён.'); else notifyListeners();
  }

  Future<void> _playToasty() async {
    if (!_settings.toastyEnabled) return;
    _toastyTimer?.cancel();
    _showToasty = true; notifyListeners();
    try { await _toastyPlayer.stop(); await _toastyPlayer.play(AssetSource('audio/toasty.mp3')); } catch (_) {}
    _toastyTimer = Timer(const Duration(milliseconds: 1700), () { _showToasty = false; notifyListeners(); });
  }

  VpnNode? _byId(String id) { for (final node in _nodes) if (node.id == id) return node; return null; }
  void _replace(VpnNode node) { final index = _nodes.indexWhere((item) => item.id == node.id); if (index >= 0) _nodes[index] = node; }
  Future<void> _persistNodes() => _storage.saveNodes(_nodes);
  void _setMessage(String value) { _message = value; notifyListeners(); }

  @override
  void dispose() {
    _toastyTimer?.cancel();
    _stateSub?.cancel(); _trafficSub?.cancel();
    unawaited(_toastyPlayer.dispose()); _generator.dispose(); unawaited(_core.dispose());
    super.dispose();
  }
}
