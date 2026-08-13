import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/core_factory.dart';
import '../core/vpn_core.dart';
import '../models/app_settings.dart';
import '../models/source_definition.dart';
import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';
import '../utils/node_parser.dart';
import 'catalog_service.dart';
import 'latency_service.dart';
import 'storage_service.dart';
import 'warpgen_bridge.dart';
import 'warp_provisioning_service.dart';

class AppController extends ChangeNotifier {
  AppController()
    : core = createVpnCore(),
      storage = StorageService(),
      catalog = CatalogService(),
      warpGen = WarpGenBridge(),
      warpProvisioning = WarpProvisioningService() {
    latency = LatencyService(core);
  }

  final VpnCore core;
  final StorageService storage;
  final CatalogService catalog;
  final WarpGenBridge warpGen;
  final WarpProvisioningService warpProvisioning;
  late final LatencyService latency;

  AppSettings settings = const AppSettings();
  List<VpnNode> nodes = <VpnNode>[];
  List<SourceDefinition> sources = <SourceDefinition>[];
  VpnProtocol? selectedProtocol;
  String search = '';
  bool whitelistOnly = false;
  bool favoritesOnly = false;
  String? selectedNodeId;
  VpnCoreState coreState = VpnCoreState.disconnected;
  TrafficSnapshot traffic = const TrafficSnapshot();
  bool loading = true;
  bool refreshing = false;
  bool testingAll = false;
  bool importingWarpGen = false;
  int testingCompleted = 0;
  int testingTotal = 0;
  String? message;
  DateTime? lastRefresh;

  final Map<String, DateTime> _quarantinedNodes = <String, DateTime>{};
  StreamSubscription<VpnCoreState>? _stateSub;
  StreamSubscription<TrafficSnapshot>? _trafficSub;
  Timer? _autoRefreshTimer;

  VpnNode? get selectedNode {
    for (final node in nodes) {
      if (node.id == selectedNodeId) return node;
    }
    return null;
  }

  bool get connected => coreState == VpnCoreState.connected;
  bool get busy =>
      coreState == VpnCoreState.preparing ||
      coreState == VpnCoreState.connecting ||
      coreState == VpnCoreState.disconnecting;

  List<VpnNode> get regularNodes =>
      nodes.where((node) => node.protocol != VpnProtocol.warp).toList();

  List<VpnNode> get warpNodes {
    final result = nodes
        .where((node) => node.protocol == VpnProtocol.warp)
        .toList();
    result.sort((a, b) => a.routeScore.compareTo(b.routeScore));
    return result;
  }

  List<VpnNode> get visibleRegularNodes => _filteredNodes(includeWarp: false);

  List<VpnNode> get visibleNodes => _filteredNodes(includeWarp: true);

  int get workingCount => nodes
      .where(
        (node) =>
            node.health == NodeHealth.online || node.health == NodeHealth.slow,
      )
      .length;

  int get unavailableCount =>
      nodes.where((node) => node.health == NodeHealth.offline).length;

  int get readyWarpCount =>
      warpNodes.where((node) => node.health == NodeHealth.ready).length;

  int countFor(VpnProtocol protocol) =>
      nodes.where((node) => node.protocol == protocol).length;

  int get whitelistCount => nodes.where((node) => node.isWhitelist).length;
  int get favoriteCount => nodes.where((node) => node.isFavorite).length;

  List<VpnNode> _filteredNodes({required bool includeWarp}) {
    final query = search.trim().toLowerCase();
    final filtered = nodes.where((node) {
      if (!includeWarp && node.protocol == VpnProtocol.warp) return false;
      if (selectedProtocol != null && node.protocol != selectedProtocol) {
        return false;
      }
      if (settings.hideOffline && node.health == NodeHealth.offline) {
        return false;
      }
      if (whitelistOnly && !node.isWhitelist) return false;
      if (favoritesOnly && !node.isFavorite) return false;
      if (query.isEmpty) return true;
      return node.name.toLowerCase().contains(query) ||
          node.countryName.toLowerCase().contains(query) ||
          node.host.toLowerCase().contains(query) ||
          node.source.toLowerCase().contains(query) ||
          node.protocol.label.toLowerCase().contains(query);
    }).toList();
    filtered.sort(_compareNodes);
    return filtered;
  }

  int _compareNodes(VpnNode a, VpnNode b) {
    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
    if (settings.preferWhitelist && a.isWhitelist != b.isWhitelist) {
      return a.isWhitelist ? -1 : 1;
    }
    return a.routeScore.compareTo(b.routeScore);
  }

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    try {
      settings = await storage.loadSettings();
      _quarantinedNodes
        ..clear()
        ..addAll(await storage.loadQuarantinedNodes());
      _pruneQuarantine();
      nodes = (await storage.loadNodes())
          .where((node) => !_isQuarantined(node.id))
          .toList();
      final savedSources = await storage.loadSources();
      final bundledSources = await catalog.loadBundledSources();
      sources = _mergeSources(savedSources, bundledSources);
      await storage.saveSources(sources);
      selectedNodeId = await storage.loadSelectedNodeId();
      lastRefresh = await storage.loadLastRefresh();
      if (nodes.isEmpty) {
        nodes = await catalog.loadBundledCatalog();
        await storage.saveNodes(nodes);
      }
      if (!nodes.any((node) => node.id == selectedNodeId)) {
        selectedNodeId = null;
      }
      try {
        await core.initialize();
      } catch (error) {
        message = 'Android VPN-ядро не инициализировано: $error';
      }
      _stateSub = core.stateStream.listen((value) {
        coreState = value;
        notifyListeners();
      });
      _trafficSub = core.trafficStream.listen((value) {
        traffic = value;
        notifyListeners();
      });
      _configureTimer();
      if (settings.autoRefresh) {
        unawaited(refreshCatalog(silent: true));
      }
      if (settings.autoGenerateWarp && warpNodes.isEmpty) {
        unawaited(generateWarpPool(silent: true));
      }
    } catch (error) {
      message = 'Приложение запущено в безопасном режиме: $error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectProtocol(VpnProtocol? protocol) {
    selectedProtocol = protocol;
    whitelistOnly = false;
    favoritesOnly = false;
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void setWhitelistOnly(bool value) {
    whitelistOnly = value;
    if (value) {
      selectedProtocol = null;
      favoritesOnly = false;
    }
    notifyListeners();
  }

  void setFavoritesOnly(bool value) {
    favoritesOnly = value;
    if (value) {
      selectedProtocol = null;
      whitelistOnly = false;
    }
    notifyListeners();
  }

  Future<void> selectNode(VpnNode node) async {
    selectedNodeId = node.id;
    await storage.saveSelectedNodeId(node.id);
    notifyListeners();
  }

  Future<void> toggleFavorite(VpnNode node) async {
    _replaceNode(node.copyWith(isFavorite: !node.isFavorite));
    await storage.saveNodes(nodes);
  }

  Future<void> removeNode(VpnNode node) async {
    nodes.removeWhere((item) => item.id == node.id);
    if (selectedNodeId == node.id) {
      selectedNodeId = null;
      await storage.saveSelectedNodeId(null);
    }
    await storage.saveNodes(nodes);
    notifyListeners();
  }

  Future<void> connectNode(VpnNode node) async {
    if (busy) return;
    message = null;
    notifyListeners();
    try {
      if (connected) await core.disconnect();
      await selectNode(node);
      await core.connect(node, settings);
      unawaited(_validateAfterConnect(node));
    } catch (error) {
      await _recordConnectionFailure(
        node,
        error.toString(),
        confirmedTunnelFailure: false,
      );
      message = 'Подключение не выполнено: $error';
      notifyListeners();
    }
  }

  Future<void> connectOrDisconnect() async {
    message = null;
    notifyListeners();
    if (connected || busy) {
      await core.disconnect();
      return;
    }
    final node = settings.autoSelectBest
        ? _resolveBestNode()
        : (selectedNode ?? (nodes.isNotEmpty ? nodes.first : null));
    if (node == null) {
      message = 'Нет доступных конфигураций. Обнови каталог.';
      notifyListeners();
      return;
    }
    await connectNode(node);
  }

  VpnNode? _resolveBestNode() {
    var candidates = nodes
        .where(
          (node) =>
              node.health != NodeHealth.offline &&
              node.health != NodeHealth.invalid,
        )
        .toList();
    if (settings.preferWhitelist) {
      final whitelist = candidates.where((node) => node.isWhitelist).toList();
      if (whitelist.isNotEmpty) candidates = whitelist;
    }
    if (candidates.isEmpty) return selectedNode;
    candidates.sort(_compareNodes);
    final measured = candidates
        .where(
          (node) =>
              node.health == NodeHealth.online ||
              node.health == NodeHealth.slow,
        )
        .toList();
    return measured.isNotEmpty ? measured.first : candidates.first;
  }

  Future<void> _validateAfterConnect(VpnNode node) async {
    final result = await core.validateConnected(const Duration(seconds: 12));
    if (selectedNodeId != node.id || !connected) return;
    if (result.success) {
      _replaceNode(
        node.copyWith(
          latencyMs: result.latencyMs,
          health: NodeHealth.online,
          lastChecked: DateTime.now(),
          metadata: <String, dynamic>{
            ...node.metadata,
            'probe_kind': 'connected_tunnel',
            'probe_detail': result.detail,
            'url_test_failures': 0,
            'connection_failures': 0,
          },
        ),
      );
      await storage.saveNodes(nodes);
      message = 'Подключено. ${result.detail}';
      notifyListeners();
      return;
    }
    if (result.definitive) {
      await core.disconnect();
      await _recordConnectionFailure(
        node,
        result.detail,
        confirmedTunnelFailure: true,
      );
      message = 'VPN не пропускает интернет: ${result.detail}';
    } else {
      message =
          'VPN подключён, но автоматическая проверка не завершена: '
          '${result.detail}';
    }
    notifyListeners();
  }

  Future<void> _recordConnectionFailure(
    VpnNode node,
    String detail, {
    required bool confirmedTunnelFailure,
  }) async {
    final current = _currentNode(node.id) ?? node;
    final previousFailures = _metadataInt(current, 'connection_failures');
    final failures = confirmedTunnelFailure
        ? previousFailures + 1
        : previousFailures;
    final updated = current.copyWith(
      clearLatency: confirmedTunnelFailure,
      health: confirmedTunnelFailure ? NodeHealth.offline : NodeHealth.unknown,
      lastChecked: DateTime.now(),
      metadata: <String, dynamic>{
        ...current.metadata,
        'connection_failures': failures,
        'probe_detail': detail,
        'probe_kind': confirmedTunnelFailure
            ? 'connected_tunnel'
            : 'connection_setup',
      },
    );
    _replaceNode(updated);
    if (confirmedTunnelFailure &&
        settings.autoRemoveUnavailable &&
        failures >= settings.removeAfterFailures) {
      await _quarantineAndRemove(updated);
    } else {
      await storage.saveNodes(nodes);
    }
  }

  Future<bool> testNode(
    VpnNode node, {
    bool announce = true,
    bool? baseInternetAvailable,
  }) async {
    if (!nodes.any((item) => item.id == node.id)) return false;
    if (connected || busy) {
      if (announce) {
        message =
            'URL Test не подключает и не отключает VPN. '
            'Сначала вручную отключи активное соединение.';
        notifyListeners();
      }
      return false;
    }

    final current = _currentNode(node.id) ?? node;
    _replaceNode(current.copyWith(health: NodeHealth.checking));
    final timeout = Duration(milliseconds: settings.urlTestTimeoutMs);
    try {
      {
        final baseAvailable =
            baseInternetAvailable ?? await latency.hasBaseInternet(timeout);
        if (!baseAvailable) {
          _replaceNode(
            current.copyWith(
              clearLatency: true,
              health: NodeHealth.unknown,
              lastChecked: DateTime.now(),
              metadata: <String, dynamic>{
                ...current.metadata,
                'probe_detail':
                    'Базовый интернет недоступен; профиль не '
                    'помечен нерабочим и не удалён.',
              },
            ),
          );
          await storage.saveNodes(nodes);
          if (announce) {
            message =
                'Нет обычного интернета. URL Test отменён, сервер не удалён.';
            notifyListeners();
          }
          return false;
        }
      }

      final result = await latency.check(current, timeout, settings: settings);
      return _applyProbeResult(current, result, announce: announce);
    } catch (error) {
      _replaceNode(
        current.copyWith(
          clearLatency: true,
          health: NodeHealth.unknown,
          lastChecked: DateTime.now(),
          metadata: <String, dynamic>{
            ...current.metadata,
            'probe_detail': 'Ошибка механизма URL Test: $error',
          },
        ),
      );
      await storage.saveNodes(nodes);
      if (announce) {
        message = 'URL Test не завершён, сервер не удалён: $error';
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> _applyProbeResult(
    VpnNode node,
    ProbeResult result, {
    required bool announce,
  }) async {
    if (result.success && result.kind == ProbeKind.configValidation) {
      _replaceNode(
        node.copyWith(
          clearLatency: true,
          health: NodeHealth.ready,
          lastChecked: DateTime.now(),
          metadata: <String, dynamic>{
            ...node.metadata,
            'probe_detail': result.detail,
            'probe_kind': 'config_validation',
          },
        ),
      );
      await storage.saveNodes(nodes);
      if (announce) {
        message = result.detail;
        notifyListeners();
      }
      return true;
    }

    if (result.success && result.latencyMs != null) {
      _replaceNode(
        node.copyWith(
          latencyMs: result.latencyMs,
          health: result.latencyMs! > 700 ? NodeHealth.slow : NodeHealth.online,
          lastChecked: DateTime.now(),
          metadata: <String, dynamic>{
            ...node.metadata,
            'probe_detail': result.detail,
            'probe_kind': 'url_test',
            'url_test_failures': 0,
          },
        ),
      );
      await storage.saveNodes(nodes);
      if (announce) {
        message = 'URL Test: ${result.latencyMs} мс. VPN не подключался.';
        notifyListeners();
      }
      return true;
    }

    if (!result.definitive) {
      _replaceNode(
        node.copyWith(
          clearLatency: true,
          health: NodeHealth.unknown,
          lastChecked: DateTime.now(),
          metadata: <String, dynamic>{
            ...node.metadata,
            'probe_detail': result.detail,
          },
        ),
      );
      await storage.saveNodes(nodes);
      if (announce) {
        message = 'Проверка не завершена, сервер сохранён: ${result.detail}';
        notifyListeners();
      }
      return false;
    }

    if (result.kind == ProbeKind.configValidation) {
      await _quarantineAndRemove(node);
      if (announce) {
        message = 'Повреждённый конфиг удалён: ${result.detail}';
        notifyListeners();
      }
      return false;
    }

    final failures = _metadataInt(node, 'url_test_failures') + 1;
    final updated = node.copyWith(
      clearLatency: true,
      health: NodeHealth.offline,
      lastChecked: DateTime.now(),
      metadata: <String, dynamic>{
        ...node.metadata,
        'probe_detail': result.detail,
        'probe_kind': 'url_test',
        'url_test_failures': failures,
      },
    );
    _replaceNode(updated);
    final remove =
        settings.autoRemoveUnavailable &&
        failures >= settings.removeAfterFailures;
    if (remove) {
      await _quarantineAndRemove(updated);
    } else {
      await storage.saveNodes(nodes);
    }
    if (announce) {
      message = remove
          ? 'Сервер удалён после $failures подтверждённых провалов URL Test.'
          : 'Сервер не ответил: попытка $failures из '
                '${settings.removeAfterFailures}. Он пока сохранён.';
      notifyListeners();
    }
    return false;
  }

  Future<void> testVisibleNodes() async {
    await _testNodeQueue(
      visibleRegularNodes.take(100).toList(),
      label: 'видимых серверов',
      showSummary: true,
    );
  }

  Future<void> testAllRegularNodes() async {
    await _testNodeQueue(
      regularNodes.take(200).toList(),
      label: 'серверов каталога',
      showSummary: true,
    );
  }

  Future<void> testAllWarpNodes() async {
    await _testNodeQueue(
      warpNodes.take(20).toList(),
      label: 'WARP-конфигов',
      showSummary: true,
      forceSequential: true,
    );
  }

  Future<void> _testNodeQueue(
    List<VpnNode> queue, {
    required String label,
    required bool showSummary,
    bool forceSequential = false,
  }) async {
    if (testingAll || queue.isEmpty) return;
    if (connected || busy) {
      if (showSummary) {
        message =
            'Проверка требует свободного Android VPN. Сначала отключи активное соединение.';
        notifyListeners();
      }
      return;
    }

    testingAll = true;
    testingCompleted = 0;
    testingTotal = queue.length;
    if (showSummary) message = null;
    notifyListeners();

    var cursor = 0;
    var working = 0;
    var unavailable = 0;
    var removed = 0;
    final baseAvailable = await latency.hasBaseInternet(
      Duration(milliseconds: settings.urlTestTimeoutMs),
    );
    if (!baseAvailable) {
      testingAll = false;
      testingCompleted = 0;
      testingTotal = 0;
      if (showSummary) {
        message =
            'Базовый интернет недоступен. Серверы не проверялись и не удалялись.';
      }
      notifyListeners();
      return;
    }

    Future<void> worker() async {
      while (true) {
        if (cursor >= queue.length) return;
        final current = queue[cursor++];
        final existed = nodes.any((node) => node.id == current.id);
        final ok = await testNode(
          current,
          announce: false,
          baseInternetAvailable: true,
        );
        if (ok) {
          working += 1;
        } else if (existed && !nodes.any((node) => node.id == current.id)) {
          removed += 1;
        } else {
          unavailable += 1;
        }
        testingCompleted += 1;
        notifyListeners();
      }
    }

    try {
      final workerCount = forceSequential
          ? 1
          : settings.urlTestConcurrency
                .clamp(1, 4)
                .toInt()
                .clamp(1, queue.length)
                .toInt();
      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      );
      nodes = CatalogService.capAndDedupe(
        nodes,
        maxPerProtocol: settings.maxPerProtocol,
      );
      await storage.saveNodes(nodes);
      if (showSummary) {
        message =
            'URL Test завершён: $working доступны, $unavailable не '
            'ответили, $removed удалено из ${queue.length} $label.';
      }
    } catch (error) {
      if (showSummary) message = 'URL Test завершился с ошибкой: $error';
    } finally {
      testingAll = false;
      notifyListeners();
    }
  }

  Future<void> refreshCatalog({bool silent = false}) async {
    if (refreshing) return;
    if (silent && connected && settings.pauseRefreshWhileConnected) return;
    refreshing = true;
    if (!silent) message = null;
    notifyListeners();
    var shouldAutoTest = false;
    try {
      final previous = <String, VpnNode>{
        for (final node in nodes) node.id: node,
      };
      final incoming = <VpnNode>[];
      try {
        incoming.addAll(
          await catalog.loadRemoteCatalog(settings.remoteCatalogUrl),
        );
      } catch (_) {
        // Enabled sources below remain authoritative.
      }
      final result = await catalog.refreshSources(
        sources,
        maxPerProtocol: settings.maxPerProtocol,
      );
      incoming.addAll(result.nodes);
      incoming.removeWhere((node) => _isQuarantined(node.id));
      if (incoming.isEmpty) {
        if (!silent) {
          message =
              'Источники временно не ответили. Сохранён предыдущий каталог '
              'из ${nodes.length} конфигураций.';
        }
        return;
      }

      final favorites = <String, bool>{
        for (final node in nodes) node.id: node.isFavorite,
      };
      final merged = _mergeCatalogBuckets(
        nodes,
        incoming,
        favorites,
      ).map((node) => _preserveRuntime(node, previous[node.id])).toList();
      nodes = CatalogService.capAndDedupe(
        merged,
        maxPerProtocol: settings.maxPerProtocol,
      );
      if (!nodes.any((node) => node.id == selectedNodeId)) {
        selectedNodeId = null;
        await storage.saveSelectedNodeId(null);
      }
      await _saveSuccessfulRefresh();
      shouldAutoTest =
          settings.autoTestAfterRefresh &&
          !connected &&
          !testingAll &&
          regularNodes.isNotEmpty;
      if (!silent) {
        final failed = result.failedSources.isEmpty
            ? ''
            : ' Не ответили: ${result.failedSources.join(', ')}.';
        final rejected = result.rejectedProfiles == 0
            ? ''
            : ' Отсеяно несовместимых: ${result.rejectedProfiles}.';
        message =
            'Каталог обновлён: ${nodes.length} конфигураций, '
            '${regularNodes.length} обычных и ${warpNodes.length} WARP.'
            '$rejected$failed';
      }
    } catch (error) {
      if (!silent) message = 'Не удалось обновить каталог: $error';
    } finally {
      refreshing = false;
      notifyListeners();
      if (shouldAutoTest) {
        unawaited(
          _testNodeQueue(
            regularNodes.take(40).toList(),
            label: 'новых серверов',
            showSummary: false,
          ),
        );
      }
    }
  }

  VpnNode _preserveRuntime(VpnNode fresh, VpnNode? previous) {
    if (previous == null) return fresh;
    return fresh.copyWith(
      latencyMs: previous.latencyMs,
      clearLatency: previous.latencyMs == null,
      health: previous.health == NodeHealth.checking
          ? NodeHealth.unknown
          : previous.health,
      isFavorite: previous.isFavorite,
      lastChecked: previous.lastChecked,
      metadata: <String, dynamic>{
        ...fresh.metadata,
        if (previous.metadata.containsKey('url_test_failures'))
          'url_test_failures': previous.metadata['url_test_failures'],
        if (previous.metadata.containsKey('connection_failures'))
          'connection_failures': previous.metadata['connection_failures'],
        if (previous.metadata.containsKey('probe_detail'))
          'probe_detail': previous.metadata['probe_detail'],
        if (previous.metadata.containsKey('probe_kind'))
          'probe_kind': previous.metadata['probe_kind'],
      },
    );
  }

  List<VpnNode> _mergeCatalogBuckets(
    List<VpnNode> previous,
    List<VpnNode> incoming,
    Map<String, bool> favorites,
  ) {
    final local = previous.where(_isLocalNode).toList();
    final selected = <VpnNode>[...local];

    for (final subtype in CatalogService.whitelistSubtypes) {
      final fresh = incoming
          .where((node) => node.isWhitelist && node.whitelistSubtype == subtype)
          .toList();
      selected.addAll(
        fresh.isNotEmpty
            ? fresh
            : previous.where(
                (node) => node.isWhitelist && node.whitelistSubtype == subtype,
              ),
      );
    }

    for (final protocol in VpnProtocol.values) {
      if (protocol == VpnProtocol.warp) continue;
      final fresh = incoming
          .where((node) => !node.isWhitelist && node.protocol == protocol)
          .toList();
      selected.addAll(
        fresh.isNotEmpty
            ? fresh
            : previous.where(
                (node) => !node.isWhitelist && node.protocol == protocol,
              ),
      );
    }

    return CatalogService.capAndDedupe(
      selected,
      maxPerProtocol: settings.maxPerProtocol,
    ).map((node) {
      return favorites[node.id] == true
          ? node.copyWith(isFavorite: true)
          : node;
    }).toList();
  }

  bool _isLocalNode(VpnNode node) {
    final source = node.source.toLowerCase();
    return node.protocol == VpnProtocol.warp ||
        source.contains('ручной') ||
        source.contains('локальн') ||
        source.contains('импорт');
  }

  Future<void> _saveSuccessfulRefresh() async {
    await storage.saveNodes(nodes);
    lastRefresh = DateTime.now();
    await storage.saveLastRefresh(lastRefresh!);
  }

  bool get warpWebsiteCaptureSupported => warpGen.supported;

  Future<int> generateWarpPool({bool silent = false}) async {
    if (importingWarpGen) return 0;
    importingWarpGen = true;
    if (!silent) message = null;
    notifyListeners();
    try {
      final configs = await warpProvisioning.generate(
        count: settings.warpPoolSize,
      );
      final additions = <VpnNode>[];
      for (var index = 0; index < configs.length; index++) {
        final parsed = _parseOneWarp(
          configs[index],
          'Автоматический WARP / endpoint rotation',
        );
        additions.add(
          parsed.copyWith(
            name: 'WARP Auto ${index + 1} · ${parsed.endpoint}',
            metadata: <String, dynamic>{
              ...parsed.metadata,
              'auto_generated': true,
              'endpoint_variant': index + 1,
            },
          ),
        );
      }
      nodes = CatalogService.capAndDedupe(<VpnNode>[
        ...additions,
        ...nodes,
      ], maxPerProtocol: settings.maxPerProtocol);
      if (additions.isNotEmpty) {
        selectedNodeId = additions.first.id;
        await storage.saveSelectedNodeId(selectedNodeId);
      }
      await storage.saveNodes(nodes);
      if (!silent) {
        message =
            'Создано ${additions.length} WARP-вариантов. Нажми '
            '«Проверить все WARP», чтобы оставить только рабочие.';
      }
      return additions.length;
    } catch (error) {
      if (!silent) message = 'Автогенерация WARP не выполнена: $error';
      return 0;
    } finally {
      importingWarpGen = false;
      notifyListeners();
    }
  }

  Future<void> importWarpFromWebsite({
    required String url,
    required String sourceName,
  }) async {
    if (importingWarpGen) return;
    importingWarpGen = true;
    message = null;
    notifyListeners();
    try {
      final raw = await warpGen.openAndCapture(url);
      if (raw == null) {
        message = 'Получение WARP отменено.';
        return;
      }
      final node = _parseOneWarp(raw, sourceName);
      await _storeWarp(node);
      message =
          'Добавлен один WARP-конфиг с $sourceName. '
          'VPN не включался; нажми «Подключить», когда захочешь его использовать.';
    } catch (error) {
      message = 'Не удалось получить WARP с $sourceName: $error';
    } finally {
      importingWarpGen = false;
      notifyListeners();
    }
  }

  Future<int> importWarpFile() async {
    if (importingWarpGen) return 0;
    importingWarpGen = true;
    message = null;
    notifyListeners();
    try {
      const typeGroup = XTypeGroup(
        label: 'WireGuard / AmneziaWG',
        extensions: <String>['conf', 'txt'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (file == null) return 0;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('Выбранный файл пустой.');
      final raw = utf8.decode(bytes, allowMalformed: true);
      final node = _parseOneWarp(raw, 'Ручной импорт WARP');
      await _storeWarp(node);
      message =
          'Один WARP-конфиг импортирован. Он не подключался автоматически.';
      return 1;
    } catch (error) {
      message = 'Не удалось импортировать WARP: $error';
      return 0;
    } finally {
      importingWarpGen = false;
      notifyListeners();
    }
  }

  VpnNode _parseOneWarp(String raw, String sourceName) {
    final config = NodeParser.extractSingleWgQuick(raw) ?? raw;
    final node = NodeParser.parse(config, source: sourceName);
    if (node == null || node.protocol != VpnProtocol.warp) {
      throw const FormatException(
        'Получен не один полноценный [Interface]/[Peer] конфиг.',
      );
    }
    final compatibility = NodeParser.catalogCompatibilityError(node);
    if (compatibility != null) {
      throw FormatException('Конфигурация отклонена: $compatibility');
    }
    return node.copyWith(
      health: NodeHealth.ready,
      lastChecked: DateTime.now(),
      metadata: <String, dynamic>{
        ...node.metadata,
        'engine': 'amneziawg',
        'probe_kind': 'config_validation',
        'probe_detail': 'Структура WARP-конфига проверена.',
      },
    );
  }

  Future<void> _storeWarp(VpnNode node) async {
    nodes.removeWhere((item) => item.id == node.id);
    _quarantinedNodes.remove(node.id);
    nodes = CatalogService.capAndDedupe(<VpnNode>[
      node,
      ...nodes,
    ], maxPerProtocol: settings.maxPerProtocol);
    selectedNodeId = node.id;
    await storage.saveNodes(nodes);
    await storage.saveSelectedNodeId(node.id);
    await storage.saveQuarantinedNodes(_quarantinedNodes);
  }

  Future<int> importText(String raw, {String source = 'Ручной импорт'}) async {
    final additions = <VpnNode>[];
    final embeddedWarp = NodeParser.extractSingleWgQuick(raw);
    if (embeddedWarp != null) {
      additions.add(_parseOneWarp(embeddedWarp, source));
    }
    for (final link in NodeParser.extractLinks(raw)) {
      final node = NodeParser.parse(link, source: source);
      if (node != null && NodeParser.isCatalogCompatible(node)) {
        additions.add(node);
      }
    }
    if (additions.isEmpty) return 0;
    nodes = CatalogService.capAndDedupe(<VpnNode>[
      ...additions,
      ...nodes,
    ], maxPerProtocol: settings.maxPerProtocol);
    selectedNodeId = additions.first.id;
    await storage.saveNodes(nodes);
    await storage.saveSelectedNodeId(selectedNodeId);
    notifyListeners();
    return additions.length;
  }

  Future<void> addSource(String name, String url) async {
    final source = SourceDefinition(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? 'Пользовательский источник' : name.trim(),
      url: url.trim(),
    );
    sources = <SourceDefinition>[...sources, source];
    await storage.saveSources(sources);
    notifyListeners();
  }

  Future<void> toggleSource(SourceDefinition source) async {
    sources = sources
        .map(
          (item) => item.id == source.id
              ? item.copyWith(enabled: !item.enabled)
              : item,
        )
        .toList();
    await storage.saveSources(sources);
    notifyListeners();
  }

  Future<void> removeSource(SourceDefinition source) async {
    sources.removeWhere((item) => item.id == source.id);
    await storage.saveSources(sources);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings value) async {
    settings = value;
    await storage.saveSettings(settings);
    _configureTimer();
    notifyListeners();
  }

  Future<void> onAppResumed() async {
    if (!settings.autoRefresh || !settings.refreshOnResume) return;
    if (connected && settings.pauseRefreshWhileConnected) return;
    final interval = Duration(minutes: settings.refreshMinutes);
    if (lastRefresh == null ||
        DateTime.now().difference(lastRefresh!) >= interval) {
      await refreshCatalog(silent: true);
    }
  }

  List<SourceDefinition> _mergeSources(
    List<SourceDefinition> saved,
    List<SourceDefinition> bundled,
  ) {
    final byId = <String, SourceDefinition>{
      for (final source in saved) source.id: source,
    };
    for (final source in bundled) {
      final previous = byId[source.id];
      byId[source.id] = previous == null
          ? source
          : SourceDefinition(
              id: source.id,
              name: source.name,
              url: source.url,
              type: source.type,
              enabled: source.enabled && previous.enabled,
              maxPages: source.maxPages,
              mirrorGroup: source.mirrorGroup,
              catalogClass: source.catalogClass,
              catalogSubtype: source.catalogSubtype,
            );
    }
    return byId.values.toList();
  }

  int _metadataInt(VpnNode node, String key) =>
      int.tryParse(node.metadata[key]?.toString() ?? '') ?? 0;

  VpnNode? _currentNode(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  void _replaceNode(VpnNode updated) {
    final index = nodes.indexWhere((node) => node.id == updated.id);
    if (index >= 0) nodes[index] = updated;
    notifyListeners();
  }

  bool _isQuarantined(String id) {
    final until = _quarantinedNodes[id];
    return until != null && until.isAfter(DateTime.now());
  }

  void _pruneQuarantine() {
    final now = DateTime.now();
    _quarantinedNodes.removeWhere((_, until) => !until.isAfter(now));
  }

  Future<void> _quarantineAndRemove(VpnNode node) async {
    nodes.removeWhere((item) => item.id == node.id);
    _quarantinedNodes[node.id] = DateTime.now().add(
      Duration(hours: settings.quarantineHours),
    );
    if (selectedNodeId == node.id) {
      selectedNodeId = null;
      await storage.saveSelectedNodeId(null);
    }
    await storage.saveNodes(nodes);
    await storage.saveQuarantinedNodes(_quarantinedNodes);
    notifyListeners();
  }

  void _configureTimer() {
    _autoRefreshTimer?.cancel();
    if (!settings.autoRefresh) return;
    _autoRefreshTimer = Timer.periodic(
      Duration(minutes: settings.refreshMinutes),
      (_) => unawaited(refreshCatalog(silent: true)),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _stateSub?.cancel();
    _trafficSub?.cancel();
    latency.dispose();
    unawaited(core.dispose());
    catalog.dispose();
    warpProvisioning.dispose();
    super.dispose();
  }
}
