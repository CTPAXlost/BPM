enum VpnProtocol {
  warp('WARP / AmneziaWG', 'warp');

  const VpnProtocol(this.label, this.key);

  final String label;
  final String key;

  static VpnProtocol? fromUri(String raw) {
    final value = raw.trimLeft().toLowerCase();
    return value.startsWith('[interface]') ? VpnProtocol.warp : null;
  }

  static VpnProtocol? fromKey(String value) =>
      value == 'warp' ? VpnProtocol.warp : null;
}
