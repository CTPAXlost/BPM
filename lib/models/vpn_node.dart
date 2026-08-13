import 'vpn_protocol.dart';

enum NodeHealth { unknown, checking, ready, online, slow, offline, invalid }

class VpnNode {
  const VpnNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.rawConfig,
    required this.host,
    required this.port,
    this.transport = '',
    this.countryCode = '',
    this.countryName = '',
    this.source = '',
    this.latencyMs,
    this.health = NodeHealth.unknown,
    this.isFavorite = false,
    this.lastChecked,
    this.metadata = const <String, dynamic>{},
  });

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    return VpnNode(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Без названия',
      protocol: VpnProtocol.fromKey(json['protocol']?.toString() ?? '') ??
          VpnProtocol.vless,
      rawConfig:
          json['raw_config']?.toString() ?? json['uri']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: int.tryParse(json['port']?.toString() ?? '') ?? 0,
      transport: json['transport']?.toString() ?? '',
      countryCode: json['country_code']?.toString() ?? '',
      countryName: json['country_name']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      latencyMs: int.tryParse(json['latency_ms']?.toString() ?? ''),
      health: NodeHealth.values.firstWhere(
        (value) => value.name == json['health'],
        orElse: () => NodeHealth.unknown,
      ),
      isFavorite: json['favorite'] == true,
      lastChecked: DateTime.tryParse(json['last_checked']?.toString() ?? ''),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const <String, dynamic>{},
    );
  }

  final String id;
  final String name;
  final VpnProtocol protocol;
  final String rawConfig;
  final String host;
  final int port;
  final String transport;
  final String countryCode;
  final String countryName;
  final String source;
  final int? latencyMs;
  final NodeHealth health;
  final bool isFavorite;
  final DateTime? lastChecked;
  final Map<String, dynamic> metadata;

  String get endpoint => '$host:$port';

  bool get isWhitelist {
    if (metadata['catalog_class'] == 'whitelist' ||
        metadata['special_class'] == 'whitelist') {
      return true;
    }
    final haystack = '$name $source'.toLowerCase();
    return haystack.contains('белые списки') ||
        haystack.contains('white list') ||
        haystack.contains('whitelist') ||
        haystack.contains('sni-ru') ||
        haystack.contains('cidr');
  }

  String get catalogClass => isWhitelist ? 'whitelist' : 'regular';

  String get whitelistSubtype {
    final explicit = metadata['catalog_subtype']?.toString().trim().toLowerCase() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final haystack = '$name $source'.toLowerCase();
    if (haystack.contains('mobile')) return 'mobile';
    if (haystack.contains('checked') || haystack.contains('хостер')) {
      return 'cidr_checked';
    }
    if (haystack.contains('sni')) return 'sni';
    if (haystack.contains('cidr')) return 'cidr_all';
    return 'other';
  }

  String get whitelistSubtypeLabel => switch (whitelistSubtype) {
        'mobile' => 'Mobile TOP',
        'cidr_checked' => 'CIDR проверенные',
        'cidr_all' => 'CIDR полный',
        'sni' => 'SNI',
        _ => 'Другие',
      };

  int get routeScore {
    final latency = latencyMs ?? 2000;
    var score = latency;
    if (health == NodeHealth.offline || health == NodeHealth.invalid) score += 100000;
    if (health == NodeHealth.slow) score += 1500;
    if (health == NodeHealth.ready) score += 250;
    if (isFavorite) score -= 250;
    if (isWhitelist) score -= 100;
    return score;
  }

  String get flag {
    final code = countryCode.toUpperCase();
    if (code.length != 2) return '🌐';
    return String.fromCharCodes(code.codeUnits.map((unit) => unit + 127397));
  }

  VpnNode copyWith({
    String? id,
    String? name,
    VpnProtocol? protocol,
    String? rawConfig,
    String? host,
    int? port,
    String? transport,
    String? countryCode,
    String? countryName,
    String? source,
    int? latencyMs,
    bool clearLatency = false,
    NodeHealth? health,
    bool? isFavorite,
    DateTime? lastChecked,
    Map<String, dynamic>? metadata,
  }) {
    return VpnNode(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      rawConfig: rawConfig ?? this.rawConfig,
      host: host ?? this.host,
      port: port ?? this.port,
      transport: transport ?? this.transport,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      source: source ?? this.source,
      latencyMs: clearLatency ? null : latencyMs ?? this.latencyMs,
      health: health ?? this.health,
      isFavorite: isFavorite ?? this.isFavorite,
      lastChecked: lastChecked ?? this.lastChecked,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'protocol': protocol.key,
        'raw_config': rawConfig,
        'host': host,
        'port': port,
        'transport': transport,
        'country_code': countryCode,
        'country_name': countryName,
        'source': source,
        'latency_ms': latencyMs,
        'health': health.name,
        'favorite': isFavorite,
        'last_checked': lastChecked?.toIso8601String(),
        'metadata': metadata,
      };
}
