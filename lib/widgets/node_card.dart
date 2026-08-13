import 'package:flutter/material.dart';

import '../models/vpn_node.dart';
import '../theme/app_theme.dart';

class NodeCard extends StatelessWidget {
  const NodeCard({
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onConnect,
    required this.onTest,
    required this.onFavorite,
    required this.onDelete,
    this.testLabel = 'URL Test',
    super.key,
  });

  final VpnNode node;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final String testLabel;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(node);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: selected
            ? AppColors.cyan.withValues(alpha: 0.1)
            : AppColors.surface,
        border: Border.all(
          color: selected ? AppColors.cyan : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceStrong,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(node.flag, style: const TextStyle(fontSize: 23)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          node.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${node.protocol.label} · '
                          '${node.countryName.isEmpty ? node.host : node.countryName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Избранное',
                    onPressed: onFavorite,
                    icon: Icon(
                      node.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: node.isFavorite ? Colors.amber : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _Badge(
                    icon: status.icon,
                    label: status.label,
                    color: status.color,
                  ),
                  if (node.isWhitelist)
                    const _Badge(
                      icon: Icons.cell_tower_rounded,
                      label: 'Белые списки',
                      color: AppColors.violet,
                    ),
                  if (selected)
                    const _Badge(
                      icon: Icons.check_circle_rounded,
                      label: 'Выбран',
                      color: AppColors.cyan,
                    ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTest,
                      icon: const Icon(Icons.speed_rounded, size: 19),
                      label: Text(testLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.power_settings_new_rounded, size: 19),
                      label: const Text('Подключить'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _NodeStatus _statusFor(VpnNode node) {
    return switch (node.health) {
      NodeHealth.checking => const _NodeStatus(
          'Проверяется…',
          Icons.hourglass_top_rounded,
          AppColors.cyan,
        ),
      NodeHealth.ready => const _NodeStatus(
          'Конфиг готов',
          Icons.description_rounded,
          AppColors.violet,
        ),
      NodeHealth.online => _NodeStatus(
          'URL Test · ${node.latencyMs ?? 0} мс',
          Icons.check_circle_rounded,
          AppColors.mint,
        ),
      NodeHealth.slow => _NodeStatus(
          'URL Test · ${node.latencyMs ?? 0} мс · медленно',
          Icons.network_check_rounded,
          Colors.orangeAccent,
        ),
      NodeHealth.offline => const _NodeStatus(
          'URL Test не пройден',
          Icons.cloud_off_rounded,
          AppColors.danger,
        ),
      NodeHealth.invalid => const _NodeStatus(
          'Ошибка конфига',
          Icons.error_rounded,
          AppColors.danger,
        ),
      NodeHealth.unknown => const _NodeStatus(
          'Не проверен',
          Icons.help_outline_rounded,
          AppColors.textMuted,
        ),
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeStatus {
  const _NodeStatus(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}
