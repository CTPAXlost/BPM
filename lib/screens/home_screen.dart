import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/vpn_core.dart';
import '../models/app_settings.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/status_orb.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override Widget build(BuildContext context) => Consumer<AppController>(builder: (context, controller, _) {
    final node = controller.selectedNode;
    final state = switch (controller.coreState) {
      VpnCoreState.connected => 'WARP подключён',
      VpnCoreState.preparing => 'Подготовка…',
      VpnCoreState.connecting => 'Подключение…',
      VpnCoreState.disconnecting => 'Отключение…',
      VpnCoreState.error => 'Ошибка подключения',
      _ => 'WARP отключён',
    };
    return AuroraBackground(child: SafeArea(bottom: false, child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
      children: <Widget>[
        Text('POKOLENIE', style: Theme.of(context).textTheme.headlineMedium),
        const Text('WARP / AmneziaWG', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800)),
        const SizedBox(height: 44),
        Center(child: StatusOrb(state: controller.coreState, onTap: controller.connectOrDisconnect)),
        const SizedBox(height: 20),
        Text(state, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(node?.name ?? (controller.generatingWarp ? 'Создаю первый профиль…' : 'Профиль ещё не создан'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 28),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: <Widget>[
          _Line(Icons.public, 'Профиль', node?.host ?? '—'),
          const Divider(height: 24),
          _Line(Icons.call_split, 'Раздельный туннель', _splitText(controller.settings)),
          const Divider(height: 24),
          _Line(Icons.download, 'Скорость ↓', _rate(controller.traffic.downloadSpeed)),
          const SizedBox(height: 12),
          _Line(Icons.upload, 'Скорость ↑', _rate(controller.traffic.uploadSpeed)),
        ]))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: controller.busy || controller.testingAll || controller.probeInProgress ? null : controller.connectOrDisconnect,
          icon: Icon(controller.connected ? Icons.stop_circle_outlined : Icons.power_settings_new),
          label: Text(controller.connected ? 'Отключить' : node == null ? 'Создать WARP и подключить' : 'Подключить'),
        )),
      ],
    )));
  });

  static String _splitText(AppSettings settings) => switch (settings.splitTunnelMode) {
    SplitTunnelMode.off => 'выключен',
    SplitTunnelMode.include => 'только ${settings.splitTunnelPackages.length} прилож.',
    SplitTunnelMode.exclude => 'кроме ${settings.splitTunnelPackages.length} прилож.',
  };
  static String _rate(int bytes) => bytes < 1024 ? '$bytes Б/с' : bytes < 1048576 ? '${(bytes / 1024).toStringAsFixed(1)} КБ/с' : '${(bytes / 1048576).toStringAsFixed(1)} МБ/с';
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value);
  final IconData icon; final String label; final String value;
  @override Widget build(BuildContext context) => Row(children: <Widget>[Icon(icon, color: AppColors.cyan), const SizedBox(width: 12), Expanded(child: Text(label)), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800)))]);
}
