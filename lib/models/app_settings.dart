enum SplitTunnelMode { off, include, exclude }
enum VisualTheme { nightmare, symbiosis }

class AppSettings {
  const AppSettings({
    this.mtu = 1280,
    this.dns = '1.1.1.1',
    this.testTimeoutMs = 15000,
    this.autoRemoveUnavailable = true,
    this.autoGenerateWarp = true,
    this.bypassLan = true,
    this.splitTunnelMode = SplitTunnelMode.off,
    this.splitTunnelPackages = const <String>[],
    this.visualTheme = VisualTheme.symbiosis,
    this.toastyEnabled = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) =>
        int.tryParse(json[key]?.toString() ?? '') ?? fallback;
    return AppSettings(
      mtu: readInt('mtu', 1280).clamp(1180, 1500).toInt(),
      dns: json['dns']?.toString().trim().isNotEmpty == true
          ? json['dns'].toString().trim()
          : '1.1.1.1',
      testTimeoutMs: readInt(
        'test_timeout_ms',
        readInt('url_test_timeout_ms', 15000),
      ).clamp(8000, 30000).toInt(),
      autoRemoveUnavailable: json['auto_remove_unavailable'] != false,
      autoGenerateWarp: json['auto_generate_warp'] != false,
      bypassLan: json['bypass_lan'] != false,
      splitTunnelMode: SplitTunnelMode.values.firstWhere(
        (value) => value.name == json['split_tunnel_mode'],
        orElse: () => SplitTunnelMode.off,
      ),
      splitTunnelPackages:
          (json['split_tunnel_packages'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false),
      visualTheme: VisualTheme.values.firstWhere(
        (value) => value.name == json['visual_theme'],
        orElse: () => VisualTheme.symbiosis,
      ),
      toastyEnabled: json['toasty_enabled'] != false,
    );
  }

  final int mtu;
  final String dns;
  final int testTimeoutMs;
  final bool autoRemoveUnavailable;
  final bool autoGenerateWarp;
  final bool bypassLan;
  final SplitTunnelMode splitTunnelMode;
  final List<String> splitTunnelPackages;
  final VisualTheme visualTheme;
  final bool toastyEnabled;

  AppSettings copyWith({
    int? mtu,
    String? dns,
    int? testTimeoutMs,
    bool? autoRemoveUnavailable,
    bool? autoGenerateWarp,
    bool? bypassLan,
    SplitTunnelMode? splitTunnelMode,
    List<String>? splitTunnelPackages,
    VisualTheme? visualTheme,
    bool? toastyEnabled,
  }) => AppSettings(
    mtu: mtu ?? this.mtu,
    dns: dns ?? this.dns,
    testTimeoutMs: testTimeoutMs ?? this.testTimeoutMs,
    autoRemoveUnavailable:
        autoRemoveUnavailable ?? this.autoRemoveUnavailable,
    autoGenerateWarp: autoGenerateWarp ?? this.autoGenerateWarp,
    bypassLan: bypassLan ?? this.bypassLan,
    splitTunnelMode: splitTunnelMode ?? this.splitTunnelMode,
    splitTunnelPackages: splitTunnelPackages ?? this.splitTunnelPackages,
    visualTheme: visualTheme ?? this.visualTheme,
    toastyEnabled: toastyEnabled ?? this.toastyEnabled,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mtu': mtu,
    'dns': dns,
    'test_timeout_ms': testTimeoutMs,
    'auto_remove_unavailable': autoRemoveUnavailable,
    'auto_generate_warp': autoGenerateWarp,
    'bypass_lan': bypassLan,
    'split_tunnel_mode': splitTunnelMode.name,
    'split_tunnel_packages': splitTunnelPackages,
    'visual_theme': visualTheme.name,
    'toasty_enabled': toastyEnabled,
  };
}
