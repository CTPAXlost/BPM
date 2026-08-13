class SourceDefinition {
  const SourceDefinition({
    required this.id,
    required this.name,
    required this.url,
    this.type = 'subscription',
    this.catalogClass = 'regular',
    this.catalogSubtype = '',
    this.enabled = true,
    this.maxPages = 20,
    this.mirrorGroup = '',
  });

  factory SourceDefinition.fromJson(Map<String, dynamic> json) {
    return SourceDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Источник',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'subscription',
      catalogClass: json['catalog_class']?.toString() ?? 'regular',
      catalogSubtype: json['catalog_subtype']?.toString() ?? '',
      enabled: json['enabled'] != false,
      maxPages: int.tryParse(json['max_pages']?.toString() ?? '') ?? 20,
      mirrorGroup: json['mirror_group']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String url;
  final String type;
  final String catalogClass;
  final String catalogSubtype;
  final bool enabled;
  final int maxPages;
  final String mirrorGroup;

  bool get isWhitelist => catalogClass == 'whitelist';

  SourceDefinition copyWith({
    bool? enabled,
    String? name,
    String? url,
    String? catalogClass,
    String? catalogSubtype,
  }) {
    return SourceDefinition(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type,
      catalogClass: catalogClass ?? this.catalogClass,
      catalogSubtype: catalogSubtype ?? this.catalogSubtype,
      enabled: enabled ?? this.enabled,
      maxPages: maxPages,
      mirrorGroup: mirrorGroup,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'type': type,
        'catalog_class': catalogClass,
        if (catalogSubtype.isNotEmpty) 'catalog_subtype': catalogSubtype,
        'enabled': enabled,
        'max_pages': maxPages,
        if (mirrorGroup.isNotEmpty) 'mirror_group': mirrorGroup,
      };
}
