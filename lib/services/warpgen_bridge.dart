import 'dart:io';

import 'package:flutter/services.dart';

class WarpGenBridge {
  static const MethodChannel _channel = MethodChannel('app.pokolenie/warpgen');

  static const String warpGenNet = 'https://warpgen.net/';
  static const String warpGenGithub = 'https://warp-gen.github.io/';
  static const String portalWg = 'https://warp-gen1.vercel.app/';

  bool get supported => Platform.isAndroid;

  Future<String?> openAndCapture(String url) async {
    if (!supported) {
      throw UnsupportedError('Получение WARP доступно только на Android.');
    }
    if (url != warpGenNet && url != warpGenGithub && url != portalWg) {
      throw ArgumentError.value(url, 'url', 'Источник WARP не разрешён.');
    }
    final raw = await _channel.invokeMethod<String>(
      'openAndCapture',
      <String, dynamic>{'url': url},
    );
    final normalized = raw?.replaceAll('\r\n', '\n').trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
