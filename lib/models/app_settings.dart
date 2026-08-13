enum SplitTunnelMode { off, include, exclude }

class AppSettings {
  const AppSettings({
    this.mtu = 1280,
    this.dns = 'https://1.1.1.1/dns-query',
    this.autoRefresh = true,
    this.refreshMinutes = 60,
    this.refreshOnResume = true,
    this.autoTestAfterRefresh = true,
    this.maxPerProtocol = 50,
    this.urlTestTimeoutMs = 15000,
    this.urlTestConcurrency = 1,
    this.autoRemoveUnavailable = true,
    this.removeAfterFailures = 3,
    this.quarantineHours = 24,
    this.hideOffline = false,
    this.preferWhitelist = false,
    this.autoSelectBest = true,
    this.pauseRefreshWhileConnected = true,
    this.bypassLan = true,
    this.strictRoute = true,
    this.adaptiveMtu = false,
    this.splitTunnelMode = SplitTunnelMode.off,
    this.splitTunnelPackages = const <String>[],
    this.autoGenerateWarp = true,
    this.warpPoolSize = 6,
    this.remoteCatalogUrl =
        'https://raw.githubusercontent.com/CTPAXlost/Pokolenie/main/catalog/public_catalog.json',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) =>
        int.tryParse(json[key]?.toString() ?? '') ?? fallback;

    return AppSettings(
      mtu: readInt('mtu', 1280).clamp(1180, 1500).toInt(),
      dns: json['dns']?.toString() ?? 'https://1.1.1.1/dns-query',
      autoRefresh: json['auto_refresh'] != false,
      refreshMinutes: readInt('refresh_minutes', 60).clamp(15, 1440).toInt(),
      refreshOnResume: json['refresh_on_resume'] != false,
      autoTestAfterRefresh: json['auto_test_after_refresh'] != false,
      maxPerProtocol: readInt('max_per_protocol', 50).clamp(10, 250).toInt(),
      urlTestTimeoutMs: readInt(
        'url_test_timeout_ms',
        readInt('test_timeout_ms', 15000),
      ).clamp(12000, 60000).toInt(),
      // Retained in storage for backward compatibility. Real Android VPN
      // checks are always sequential because VpnService has a single owner.
      urlTestConcurrency: 1,
      autoRemoveUnavailable: json['auto_remove_unavailable'] != false,
      removeAfterFailures: readInt(
        'remove_after_failures',
        3,
      ).clamp(2, 10).toInt(),
      quarantineHours: readInt('quarantine_hours', 24).clamp(1, 168).toInt(),
      hideOffline: json['hide_offline'] == true,
      preferWhitelist: json['prefer_whitelist'] == true,
      autoSelectBest: json['auto_select_best'] != false,
      pauseRefreshWhileConnected:
          json['pause_refresh_while_connected'] != false,
      bypassLan: json['bypass_lan'] != false,
      strictRoute: json['strict_route'] != false,
      adaptiveMtu: json['adaptive_mtu'] == true,
      splitTunnelMode: SplitTunnelMode.values.firstWhere(
        (value) => value.name == json['split_tunnel_mode'],
        orElse: () => SplitTunnelMode.off,
      ),
      splitTunnelPackages:
          (json['split_tunnel_packages'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
      autoGenerateWarp: json['auto_generate_warp'] != false,
      warpPoolSize: readInt('warp_pool_size', 6).clamp(1, 12).toInt(),
      remoteCatalogUrl:
          json['remote_catalog_url']?.toString() ??
          'https://raw.githubusercontent.com/CTPAXlost/Pokolenie/main/catalog/public_catalog.json',
    );
  }

  final int mtu;
  final String dns;
  final bool autoRefresh;
  final int refreshMinutes;
  final bool refreshOnResume;
  final bool autoTestAfterRefresh;
  final int maxPerProtocol;
  final int urlTestTimeoutMs;
  final int urlTestConcurrency;
  final bool autoRemoveUnavailable;
  final int removeAfterFailures;
  final int quarantineHours;
  final bool hideOffline;
  final bool preferWhitelist;
  final bool autoSelectBest;
  final bool pauseRefreshWhileConnected;
  final bool bypassLan;
  final bool strictRoute;
  final bool adaptiveMtu;
  final SplitTunnelMode splitTunnelMode;
  final List<String> splitTunnelPackages;
  final bool autoGenerateWarp;
  final int warpPoolSize;
  final String remoteCatalogUrl;

  AppSettings copyWith({
    int? mtu,
    String? dns,
    bool? autoRefresh,
    int? refreshMinutes,
    bool? refreshOnResume,
    bool? autoTestAfterRefresh,
    int? maxPerProtocol,
    int? urlTestTimeoutMs,
    int? urlTestConcurrency,
    bool? autoRemoveUnavailable,
    int? removeAfterFailures,
    int? quarantineHours,
    bool? hideOffline,
    bool? preferWhitelist,
    bool? autoSelectBest,
    bool? pauseRefreshWhileConnected,
    bool? bypassLan,
    bool? strictRoute,
    bool? adaptiveMtu,
    SplitTunnelMode? splitTunnelMode,
    List<String>? splitTunnelPackages,
    bool? autoGenerateWarp,
    int? warpPoolSize,
    String? remoteCatalogUrl,
  }) {
    return AppSettings(
      mtu: mtu ?? this.mtu,
      dns: dns ?? this.dns,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      refreshOnResume: refreshOnResume ?? this.refreshOnResume,
      autoTestAfterRefresh: autoTestAfterRefresh ?? this.autoTestAfterRefresh,
      maxPerProtocol: maxPerProtocol ?? this.maxPerProtocol,
      urlTestTimeoutMs: urlTestTimeoutMs ?? this.urlTestTimeoutMs,
      urlTestConcurrency: urlTestConcurrency ?? this.urlTestConcurrency,
      autoRemoveUnavailable:
          autoRemoveUnavailable ?? this.autoRemoveUnavailable,
      removeAfterFailures: removeAfterFailures ?? this.removeAfterFailures,
      quarantineHours: quarantineHours ?? this.quarantineHours,
      hideOffline: hideOffline ?? this.hideOffline,
      preferWhitelist: preferWhitelist ?? this.preferWhitelist,
      autoSelectBest: autoSelectBest ?? this.autoSelectBest,
      pauseRefreshWhileConnected:
          pauseRefreshWhileConnected ?? this.pauseRefreshWhileConnected,
      bypassLan: bypassLan ?? this.bypassLan,
      strictRoute: strictRoute ?? this.strictRoute,
      adaptiveMtu: adaptiveMtu ?? this.adaptiveMtu,
      splitTunnelMode: splitTunnelMode ?? this.splitTunnelMode,
      splitTunnelPackages: splitTunnelPackages ?? this.splitTunnelPackages,
      autoGenerateWarp: autoGenerateWarp ?? this.autoGenerateWarp,
      warpPoolSize: warpPoolSize ?? this.warpPoolSize,
      remoteCatalogUrl: remoteCatalogUrl ?? this.remoteCatalogUrl,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mtu': mtu,
    'dns': dns,
    'auto_refresh': autoRefresh,
    'refresh_minutes': refreshMinutes,
    'refresh_on_resume': refreshOnResume,
    'auto_test_after_refresh': autoTestAfterRefresh,
    'max_per_protocol': maxPerProtocol,
    'url_test_timeout_ms': urlTestTimeoutMs,
    'url_test_concurrency': urlTestConcurrency,
    'auto_remove_unavailable': autoRemoveUnavailable,
    'remove_after_failures': removeAfterFailures,
    'quarantine_hours': quarantineHours,
    'hide_offline': hideOffline,
    'prefer_whitelist': preferWhitelist,
    'auto_select_best': autoSelectBest,
    'pause_refresh_while_connected': pauseRefreshWhileConnected,
    'bypass_lan': bypassLan,
    'strict_route': strictRoute,
    'adaptive_mtu': adaptiveMtu,
    'split_tunnel_mode': splitTunnelMode.name,
    'split_tunnel_packages': splitTunnelPackages,
    'auto_generate_warp': autoGenerateWarp,
    'warp_pool_size': warpPoolSize,
    'remote_catalog_url': remoteCatalogUrl,
  };
}
