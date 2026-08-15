import 'dart:io';

import 'android_vpn_core.dart';
import 'vpn_core.dart';
import 'windows_vpn_core.dart';

VpnCore createVpnCore() {
  if (Platform.isWindows) return WindowsVpnCore();
  return AndroidVpnCore();
}
