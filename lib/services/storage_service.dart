import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/source_definition.dart';
import '../models/vpn_node.dart';

class StorageService {
  static const _settingsKey = 'settings_v2';
  static const _nodesKey = 'nodes_v2';
  static const _sourcesKey = 'sources_v2';
  static const _selectedKey = 'selected_node_v2';
  static const _lastRefreshKey = 'last_refresh_v2';
  static const _quarantineKey = 'quarantined_nodes_v1';
  static const _lastWarpGenerationKey = 'last_warp_generation_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<AppSettings> loadSettings() async {
    final raw = (await _prefs).getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await (await _prefs).setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<List<VpnNode>> loadNodes() async {
    final raw = (await _prefs).getString(_nodesKey);
    if (raw == null || raw.isEmpty) return <VpnNode>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(VpnNode.fromJson)
          .where((node) => node.rawConfig.isNotEmpty)
          .toList();
    } catch (_) {
      return <VpnNode>[];
    }
  }

  Future<void> saveNodes(List<VpnNode> nodes) async {
    await (await _prefs).setString(
      _nodesKey,
      jsonEncode(nodes.map((node) => node.toJson()).toList()),
    );
  }

  Future<List<SourceDefinition>> loadSources() async {
    final raw = (await _prefs).getString(_sourcesKey);
    if (raw == null || raw.isEmpty) return <SourceDefinition>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SourceDefinition.fromJson)
          .toList();
    } catch (_) {
      return <SourceDefinition>[];
    }
  }

  Future<void> saveSources(List<SourceDefinition> sources) async {
    await (await _prefs).setString(
      _sourcesKey,
      jsonEncode(sources.map((source) => source.toJson()).toList()),
    );
  }

  Future<DateTime?> loadLastRefresh() async {
    final raw = (await _prefs).getString(_lastRefreshKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveLastRefresh(DateTime value) async {
    await (await _prefs).setString(_lastRefreshKey, value.toIso8601String());
  }

  Future<DateTime?> loadLastWarpGeneration() async {
    final raw = (await _prefs).getString(_lastWarpGenerationKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveLastWarpGeneration(DateTime value) async {
    await (await _prefs).setString(
      _lastWarpGenerationKey,
      value.toIso8601String(),
    );
  }

  Future<Map<String, DateTime>> loadQuarantinedNodes() async {
    final raw = (await _prefs).getString(_quarantineKey);
    if (raw == null || raw.isEmpty) return <String, DateTime>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return <String, DateTime>{
        for (final entry in decoded.entries)
          if (DateTime.tryParse(entry.value.toString()) != null)
            entry.key: DateTime.parse(entry.value.toString()),
      };
    } catch (_) {
      return <String, DateTime>{};
    }
  }

  Future<void> saveQuarantinedNodes(Map<String, DateTime> values) async {
    await (await _prefs).setString(
      _quarantineKey,
      jsonEncode(<String, String>{
        for (final entry in values.entries)
          entry.key: entry.value.toIso8601String(),
      }),
    );
  }

  Future<String?> loadSelectedNodeId() async {
    return (await _prefs).getString(_selectedKey);
  }

  Future<void> saveSelectedNodeId(String? id) async {
    final prefs = await _prefs;
    if (id == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, id);
    }
  }
}
