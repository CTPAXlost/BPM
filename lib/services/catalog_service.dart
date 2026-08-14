import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/source_definition.dart';
import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';
import '../utils/node_parser.dart';

class CatalogRefreshResult {
  const CatalogRefreshResult({
    required this.nodes,
    required this.loadedSources,
    required this.failedSources,
    this.rejectedProfiles = 0,
  });

  final List<VpnNode> nodes;
  final int loadedSources;
  final List<String> failedSources;
  final int rejectedProfiles;
}

class CatalogService {
  CatalogService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent = 'Pokolenie-VPN/0.9.3';
  final http.Client _client;

  Future<List<SourceDefinition>> loadBundledSources() async {
    final raw = await rootBundle.loadString('catalog/sources.json');
    final decoded = jsonDecode(raw);
    final list = decoded is Map<String, dynamic>
        ? decoded['sources'] as List<dynamic>? ?? const <dynamic>[]
        : decoded as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(SourceDefinition.fromJson)
        .where((source) => source.id.isNotEmpty && source.url.isNotEmpty)
        .toList();
  }

  Future<List<VpnNode>> loadBundledCatalog() async {
    final raw = await rootBundle.loadString('catalog/public_catalog.json');
    return _decodeCatalog(raw, source: 'Встроенный каталог');
  }

  Future<List<VpnNode>> loadBundledWarpConfigs() async {
      const profiles = <(String, String)>[
        ('assets/warp/WARP_STR8605.conf', 'WARP STR 8605'),
        ('assets/warp/WARP_STR4470.conf', 'WARP STR 4470'),
      ];
    final result = <VpnNode>[];
    for (final profile in profiles) {
      final raw = await rootBundle.loadString(profile.$1);
      final node = NodeParser.parse(raw, source: 'Встроенный бесплатный WARP');
      if (node == null || NodeParser.catalogCompatibilityError(node) != null) {
        throw FormatException('Не удалось загрузить ${profile.$2}.');
      }
      result.add(
        node.copyWith(
          name: profile.$2,
          health: NodeHealth.ready,
          metadata: <String, dynamic>{
            ...node.metadata,
            'bundled_warp': true,
          },
        ),
      );
    }
    return result;
  }

  Future<List<VpnNode>> loadRemoteCatalog(String url) async {
    if (url.trim().isEmpty) return <VpnNode>[];
    final raw = await _fetchText(
      url,
      accept: 'application/json,text/plain,*/*',
    );
    return _decodeCatalog(raw, source: 'GitHub-каталог');
  }

  Future<CatalogRefreshResult> refreshSources(
    List<SourceDefinition> sources, {
    int maxPerProtocol = 50,
  }) async {
    final enabled = sources.where((item) => item.enabled).toList();
    final grouped = <String, List<SourceDefinition>>{};
    for (final source in enabled) {
      final key = source.mirrorGroup.trim().isEmpty
          ? source.id
          : source.mirrorGroup.trim();
      grouped.putIfAbsent(key, () => <SourceDefinition>[]).add(source);
    }

    final jobs = grouped.values.toList();
    final nodes = <VpnNode>[];
    final failed = <String>[];
    var loaded = 0;
    var rejected = 0;
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= jobs.length) return;
        final mirrors = jobs[cursor++];
        var success = false;
        for (final source in mirrors) {
          try {
            final links = await _loadSourceLinks(source);
            final parsed = <VpnNode>[];
            for (final link in links) {
              final node = NodeParser.parse(
                link,
                source: source.name,
                catalogClass: source.catalogClass,
                catalogSubtype: source.catalogSubtype,
              );
              if (node == null || !NodeParser.isCatalogCompatible(node)) {
                rejected += 1;
                continue;
              }
              parsed.add(node);
            }
            if (parsed.isEmpty) {
              throw const FormatException(
                'Источник не содержит совместимых конфигураций',
              );
            }
            nodes.addAll(parsed);
            loaded += 1;
            success = true;
            break;
          } catch (_) {
            // Try the next mirror in this group.
          }
        }
        if (!success) {
          failed.add(mirrors.map((source) => source.name).join(' / '));
        }
      }
    }

    final workerCount = jobs.length.clamp(0, 4).toInt();
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return CatalogRefreshResult(
      nodes: capAndDedupe(nodes, maxPerProtocol: maxPerProtocol),
      loadedSources: loaded,
      failedSources: failed,
      rejectedProfiles: rejected,
    );
  }

  Future<List<String>> _loadSourceLinks(SourceDefinition source) async {
    if (source.type == 'v2nodes_country' ||
        source.type == 'v2nodes_seed') {
      return _crawlV2Nodes(source);
    }
    final raw = await _fetchText(
      source.url,
      accept: 'text/plain,text/html,application/json,*/*',
    );
    return NodeParser.extractLinks(raw);
  }

  Future<String> _fetchText(
    String url, {
    String accept = 'text/plain,text/html,application/json,*/*',
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('Разрешены только HTTPS-источники');
    }
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'User-Agent': _userAgent,
            'Accept': accept,
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<String>> _crawlV2Nodes(SourceDefinition source) async {
    final seed = Uri.parse(source.url);
    final listingLimit = source.maxPages.clamp(1, 20).toInt();
    final listingQueue = <Uri>[seed];
    final visitedListings = <String>{};
    final serverPages = <String>{};
    final links = <String>{};

    while (listingQueue.isNotEmpty &&
        visitedListings.length < listingLimit) {
      final current = listingQueue.removeAt(0);
      if (!visitedListings.add(current.toString())) continue;
      final html = await _fetchText(current.toString());
      links.addAll(NodeParser.extractLinks(_decodeHtmlEntities(html)));

      for (final href in _extractHrefs(html)) {
        final candidate = current.resolve(href);
        if (candidate.scheme != 'https' || candidate.host != seed.host) {
          continue;
        }
        if (RegExp(r'^/servers/\d+/?$').hasMatch(candidate.path)) {
          serverPages.add(candidate.replace(query: '', fragment: '').toString());
          continue;
        }
        final sameCountry = candidate.path == seed.path ||
            candidate.path.startsWith('${seed.path}page/') ||
            candidate.path.startsWith('${seed.path}p/');
        final pageQuery = candidate.queryParameters.containsKey('page');
        if ((sameCountry || pageQuery) &&
            !visitedListings.contains(candidate.toString()) &&
            !listingQueue.contains(candidate)) {
          listingQueue.add(candidate);
        }
      }
    }

    final pages = serverPages.take(60).toList();
    var cursor = 0;
    Future<void> serverWorker() async {
      while (true) {
        if (cursor >= pages.length) return;
        final url = pages[cursor++];
        try {
          final html = await _fetchText(url);
          links.addAll(NodeParser.extractLinks(_decodeHtmlEntities(html)));
        } catch (_) {
          // Public entries expire quickly; one dead page must not fail the feed.
        }
      }
    }

    final workers = pages.length.clamp(0, 4).toInt();
    await Future.wait(
      List<Future<void>>.generate(workers, (_) => serverWorker()),
    );
    return links.toList(growable: false);
  }

  Iterable<String> _extractHrefs(String html) sync* {
    final pattern = RegExp(
      r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty) yield _decodeHtmlEntities(value);
    }
  }

  String _decodeHtmlEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&#x3D;', '=')
      .replaceAll('&#61;', '=')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', '\u0027');

  List<VpnNode> _decodeCatalog(String raw, {required String source}) {
    final decoded = jsonDecode(raw);
    final data = decoded is Map<String, dynamic>
        ? decoded['nodes'] as List<dynamic>? ?? const <dynamic>[]
        : decoded as List<dynamic>;
    final nodes = <VpnNode>[];
    for (final item in data) {
      VpnNode? node;
      if (item is String) {
        node = NodeParser.parse(item, source: source);
      } else if (item is Map<String, dynamic>) {
        node = VpnNode.fromJson(item);
      }
      if (node != null &&
          node.rawConfig.isNotEmpty &&
          NodeParser.isCatalogCompatible(node)) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  static const whitelistSubtypes = <String>[
    'mobile',
    'cidr_checked',
    'cidr_all',
    'sni',
    'other',
  ];

  static List<VpnNode> capAndDedupe(
    Iterable<VpnNode> nodes, {
    int maxPerProtocol = 50,
  }) {
    final regularUnique = <String, VpnNode>{};
    final whitelistUnique = <String, VpnNode>{};
    for (final node in nodes) {
      if (!NodeParser.isCatalogCompatible(node)) continue;
      if (node.isWhitelist) {
        // One endpoint may legitimately be published in several anti-jamming
        // families. Dedupe inside a family, not across the whole catalog.
        whitelistUnique['${node.whitelistSubtype}:${node.id}'] = node;
      } else {
        regularUnique[node.id] = node;
      }
    }
    final cap = maxPerProtocol.clamp(1, 50).toInt();
    final result = <VpnNode>[];

    for (final subtype in whitelistSubtypes) {
      final group = whitelistUnique.values
          .where((node) => node.whitelistSubtype == subtype)
          .toList()
        ..sort((a, b) => a.routeScore.compareTo(b.routeScore));
      result.addAll(group.take(cap));
    }

    for (final protocol in VpnProtocol.values) {
      final regular = regularUnique.values
          .where((node) => node.protocol == protocol)
          .toList()
        ..sort((a, b) => a.routeScore.compareTo(b.routeScore));
      result.addAll(regular.take(cap));
    }
    return result;
  }

  void dispose() => _client.close();
}
