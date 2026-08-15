import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/vpn_node.dart';

class StorageService {
  static const _settingsKey = 'settings_v2';
  static const _nodesKey = 'nodes_v2';
  static const _selectedKey = 'selected_node_v2';
  static const _lastWarpGenerationKey = 'last_warp_generation_v1';
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  Future<AppSettings> loadSettings() async {
    final raw = (await _prefs).getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try { return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>); } catch (_) { return const AppSettings(); }
  }
  Future<void> saveSettings(AppSettings value) async => (await _prefs).setString(_settingsKey, jsonEncode(value.toJson()));
  Future<List<VpnNode>> loadNodes() async {
    final raw = (await _prefs).getString(_nodesKey);
    if (raw == null) return <VpnNode>[];
    try { return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().map(VpnNode.fromJson).toList(); } catch (_) { return <VpnNode>[]; }
  }
  Future<void> saveNodes(List<VpnNode> value) async => (await _prefs).setString(_nodesKey, jsonEncode(value.map((e) => e.toJson()).toList()));
  Future<String?> loadSelectedNodeId() async => (await _prefs).getString(_selectedKey);
  Future<void> saveSelectedNodeId(String? value) async {
    final prefs = await _prefs;
    if (value == null) await prefs.remove(_selectedKey); else await prefs.setString(_selectedKey, value);
  }
  Future<DateTime?> loadLastWarpGeneration() async {
    final raw = (await _prefs).getString(_lastWarpGenerationKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }
  Future<void> saveLastWarpGeneration(DateTime value) async => (await _prefs).setString(_lastWarpGenerationKey, value.toIso8601String());
}
