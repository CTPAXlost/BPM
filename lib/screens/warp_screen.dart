import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vpn_node.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/node_card.dart';

class WarpScreen extends StatelessWidget {
  const WarpScreen({super.key});
  @override Widget build(BuildContext context) => Consumer<AppController>(builder: (context, controller, _) {
    final remaining = controller.warpGenerationRemaining;
    return AuroraBackground(child: SafeArea(bottom: false, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: <Widget>[
        Text('WARP-профили', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text('Генератор получает один AWG-конфиг и сразу сохраняет его внутри приложения. Никакого файла в «Загрузках».', style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: <Widget>[
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: controller.generatingWarp || remaining > Duration.zero ? null : controller.generateOneWarp,
            icon: controller.generatingWarp ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: Text(controller.generatingWarp ? 'Создаю WARP…' : remaining > Duration.zero ? 'Повтор через ${(remaining.inSeconds / 60).ceil()} мин.' : 'Создать новый WARP'),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: controller.importingWarp ? null : controller.importWarpFile, icon: const Icon(Icons.file_open), label: const Text('Импортировать .conf'))),
        ]))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: controller.testingAll || controller.probeInProgress || controller.connected || controller.warpNodes.isEmpty ? null : controller.testAllWarpNodes,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(controller.testingAll ? 'Проверено ${controller.testingCompleted} из ${controller.testingTotal}' : 'Проверить все последовательно'),
        )),
        if (controller.testingAll) ...<Widget>[const SizedBox(height: 8), LinearProgressIndicator(value: controller.testingTotal == 0 ? 0 : controller.testingCompleted / controller.testingTotal)],
        const SizedBox(height: 20),
        Text('Сохранено: ${controller.warpNodes.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 10),
        if (controller.warpNodes.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('Первый профиль будет создан автоматически. Разрешение VPN при запуске не запрашивается.', textAlign: TextAlign.center)))
        else
          for (final node in controller.warpNodes) NodeCard(
            key: ValueKey(node.id), node: node, selected: controller.selectedNodeId == node.id,
            onSelect: () => controller.selectNode(node),
            onConnect: controller.testingAll || controller.probeInProgress ? null : () => controller.connectNode(node),
            onTest: controller.testingAll || controller.probeInProgress || controller.connected ? null : () => controller.testNode(node),
            onFavorite: () => controller.toggleFavorite(node),
            onDelete: () => _delete(context, controller, node),
          ),
      ],
    )));
  });

  Future<void> _delete(BuildContext context, AppController controller, VpnNode node) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Удалить WARP?'), content: Text(node.name), actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))]));
    if (yes == true) await controller.removeNode(node);
  }
}
