import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_node.dart';
import '../models/vpn_protocol.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/node_card.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final nodes = controller.visibleRegularNodes;
        return AuroraBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(controller: controller),
                _Filters(controller: controller),
                if (controller.testingAll)
                  _TestProgress(controller: controller),
                Expanded(
                  child: nodes.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: nodes.length,
                          itemBuilder: (context, index) {
                            final node = nodes[index];
                            return NodeCard(
                              node: node,
                              selected: controller.selectedNodeId == node.id,
                              onSelect: () => controller.selectNode(node),
                              onConnect: () => controller.connectNode(node),
                              onTest: () => controller.testNode(node),
                              onFavorite: () => controller.toggleFavorite(node),
                              onDelete: () => _confirmDelete(
                                context,
                                controller,
                                node,
                              ),
                            );
                          },
                        ),
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
        title: const Text('Удалить сервер?'),
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

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Серверы',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      '${controller.regularNodes.length} конфигураций · '
                      '${controller.workingCount} прошли VPN-проверку',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.testingAll || controller.connected
                    ? null
                    : controller.testVisibleNodes,
                icon: const Icon(Icons.speed_rounded),
                label: const Text('Проверить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              hintText: 'Название, страна, адрес или протокол',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Проверка временно подключает сервер и подтверждает HTTPS именно через VPN.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          FilterChip(
            label: const Text('Все'),
            selected: controller.selectedProtocol == null &&
                !controller.whitelistOnly &&
                !controller.favoritesOnly,
            onSelected: (_) => controller.selectProtocol(null),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Избранное'),
            selected: controller.favoritesOnly,
            onSelected: controller.setFavoritesOnly,
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Белые списки'),
            selected: controller.whitelistOnly,
            onSelected: controller.setWhitelistOnly,
          ),
          for (final protocol in VpnProtocol.values)
            if (protocol != VpnProtocol.warp) ...<Widget>[
              const SizedBox(width: 8),
              FilterChip(
                label: Text(protocol.label),
                selected: controller.selectedProtocol == protocol,
                onSelected: (_) => controller.selectProtocol(protocol),
              ),
            ],
        ],
      ),
    );
  }
}

class _TestProgress extends StatelessWidget {
  const _TestProgress({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.testingTotal;
    final progress = total == 0 ? null : controller.testingCompleted / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 6),
          Text(
            'Проверка подключения: ${controller.testingCompleted} из $total',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.dns_outlined, size: 52, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text(
              'По выбранным фильтрам серверов нет',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
