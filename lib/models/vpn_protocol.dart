enum VpnProtocol {
  warp('WARP', 'warp'),
  vless('VLESS', 'vless'),
  trojan('Trojan', 'trojan'),
  shadowsocks('Shadowsocks', 'ss'),
  vmess('VMess', 'vmess'),
  hysteria2('Hysteria 2', 'hysteria2'),
  tuic('TUIC', 'tuic');

  const VpnProtocol(this.label, this.key);

  final String label;
  final String key;

  static VpnProtocol? fromUri(String raw) {
    final value = raw.trimLeft().toLowerCase();
    if (value.startsWith('warp://') || value.startsWith('wg://') || value.startsWith('[interface]')) {
      return VpnProtocol.warp;
    }
    if (value.startsWith('vless://')) return VpnProtocol.vless;
    if (value.startsWith('trojan://')) return VpnProtocol.trojan;
    if (value.startsWith('ss://') || value.startsWith('shadowsocks://')) {
      return VpnProtocol.shadowsocks;
    }
    if (value.startsWith('vmess://')) return VpnProtocol.vmess;
    if (value.startsWith('hysteria2://') || value.startsWith('hy2://') || value.startsWith('hysteria://')) {
      return VpnProtocol.hysteria2;
    }
    if (value.startsWith('tuic://')) return VpnProtocol.tuic;
    return null;
  }

  static VpnProtocol? fromKey(String value) {
    for (final protocol in values) {
      if (protocol.key == value || protocol.name == value) return protocol;
    }
    return null;
  }
}
