import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_node.dart';
import '../services/app_controller.dart';
import '../services/warpgen_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/node_card.dart';

class WarpScreen extends StatelessWidget {
  const WarpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final nodes = controller.warpNodes;
        return AuroraBackground(
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              children: <Widget>[
                Text(
                  'WARP / AWG',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Автогенерация создаёт ключи прямо на устройстве. Реальная '
                  'проверка кратко поднимает WARP-туннель и измеряет HTTPS.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                _ImportCard(controller: controller),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: controller.testingAll || nodes.isEmpty
                        ? null
                        : controller.testAllWarpNodes,
                    icon: const Icon(Icons.speed_rounded),
                    label: Text(
                      controller.testingAll
                          ? '${controller.testingCompleted}/${controller.testingTotal}'
                          : 'Проверить все WARP',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Мои WARP-конфиги',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${nodes.length}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (nodes.isEmpty)
                  const _EmptyWarp()
                else
                  for (final node in nodes)
                    NodeCard(
                      node: node,
                      selected: controller.selectedNodeId == node.id,
                      testLabel: 'Проверить WARP',
                      onSelect: () => controller.selectNode(node),
                      onConnect: () => controller.connectNode(node),
                      onTest: () => controller.testNode(node),
                      onFavorite: () => controller.toggleFavorite(node),
                      onDelete: () => _confirmDelete(context, controller, node),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppController controller,
    VpnNode node,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить WARP-конфиг?'),
        content: Text(node.name),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeNode(node);
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final busy = controller.importingWarpGen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.add_link_rounded, color: AppColors.cyan),
              SizedBox(width: 9),
              Text(
                'WARP-конфигурации',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Источник Portal WG добавлен напрямую: сгенерируй конфиг в окне '
            'и приложение перехватит его для импорта.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => controller.importWarpFromWebsite(
                      url: WarpGenBridge.portalWg,
                      sourceName: 'Portal WG',
                    ),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Получить WARP как в Portal WG'),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => controller.importWarpFromWebsite(
                      url: WarpGenBridge.warpGenNet,
                      sourceName: 'WarpGen.net',
                    ),
              icon: const Icon(Icons.language_rounded),
              label: const Text('Резерв: WarpGen.net'),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : controller.generateWarpPool,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Прямая автогенерация (экспериментально)'),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : controller.importWarpFile,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('Импортировать .conf / .wg / .awg'),
            ),
          ),
          if (busy) ...<Widget>[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _EmptyWarp extends StatelessWidget {
  const _EmptyWarp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.bolt_outlined, size: 44, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'WARP-конфигов пока нет',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Добавь один конфиг с сайта или импортируй .conf.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
